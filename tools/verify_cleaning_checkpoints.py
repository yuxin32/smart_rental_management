"""Run migrations and checkpoint regressions in disposable loopback PostgreSQL.

Requires existing trusted PostgreSQL binaries. Never connects to Supabase.
Auth/Storage/cron are synthetic; no email, decoder or hosted validation claimed.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--postgres-bin', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
bin_dir = args.postgres_bin.resolve(strict=True)
for name in ('initdb.exe', 'pg_ctl.exe', 'psql.exe'):
    if not (bin_dir/name).is_file():
        raise SystemExit('Missing PostgreSQL binary: '+name)

def run(name, arguments, env, sql=None):
    if name == 'pg_ctl.exe':
        # PostgreSQL descendants can retain Windows pipe handles. Real files
        # let communicate finish after pg_ctl exits without waiting on server.
        with tempfile.TemporaryFile(mode='w+',encoding='utf-8') as output:
            result=subprocess.run([str(bin_dir/name),*arguments],env=env,
                stdout=output,stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),timeout=45)
            output.seek(0)
            message=output.read()
        if result.returncode:raise RuntimeError(name+': '+message[-4000:])
        return message
    result = subprocess.run([str(bin_dir/name), *arguments], env=env,
        input=sql, encoding='utf-8', errors='replace', capture_output=True,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=90)
    if result.returncode:
        raise RuntimeError(name+': '+result.stdout[-2000:]+result.stderr[-4000:])
    return result.stdout+result.stderr

receipts=[]
for profile in ('legacy', 'disabled'):
    workspace=Path(tempfile.mkdtemp(prefix='checkpoint-'+profile+'-',dir=args.output))
    data=workspace/'data'
    password_path=workspace/'init-password.tmp'
    password=secrets.token_urlsafe(32)
    env=os.environ.copy()
    env['PGPASSWORD']=password
    env['PGCLIENTENCODING']='UTF8'
    password_path.write_text(password,encoding='utf-8')
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0))
        port=listener.getsockname()[1]
    started=False
    log=[]
    try:
        run('initdb.exe',['-D',str(data),'-U','postgres','--pwfile='+str(password_path),
            '--auth-host=scram-sha-256','--auth-local=scram-sha-256','--encoding=UTF8','--locale=C'],env)
        password_path.unlink()
        run('pg_ctl.exe',['-D',str(data),'-l',str(workspace/'server.log'),'-w','-t','30',
            'start','-o',f'-h 127.0.0.1 -p {port} -c wal_level=logical'],env)
        started=True
        connection=['-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','postgres',
            '-v','ON_ERROR_STOP=1','-v','broad_defaults='+('true' if profile=='legacy' else 'false')]
        def execute(label,sql=None,path=None):
            log.append('CHECK '+label+'\n')
            log.append(run('psql.exe',connection+(['-f',str(path)] if path else []),env,sql))
        execute('synthetic platform shim',path=root/'supabase/tests/local_supabase_shim.sql')
        execute('synthetic cron scheduler',sql="""
            create schema cron;
            create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;
            alter table storage.objects add column owner uuid, add column owner_id text;
            grant update,delete on storage.objects to authenticated;
        """)
        migrations=sorted((root/'supabase/migrations').glob('*.sql'))
        baseline=[m for m in migrations if m.name[:14]<='20261123000046']
        # The existing integrated baseline deliberately shares a temporary ACL
        # inventory between 014 and 032; deploy it in its documented transaction.
        baseline_sql='begin;\n'+'\n'.join(m.read_text(encoding='utf-8') for m in baseline)+'\ncommit;'
        baseline_sql=baseline_sql.replace('create extension if not exists pg_cron;',
            '-- Synthetic cron.schedule was installed by the local harness.')
        execute('documented integrated baseline 001-046',sql=baseline_sql)
        acl_sql="""select coalesce(jsonb_object_agg(id,acl),'{}'::jsonb) from (
          select 'f:'||p.oid::text id,coalesce(p.proacl::text,'') acl from pg_proc p
           join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
          union all select 'r:'||c.oid::text,coalesce(c.relacl::text,'') from pg_class c
           join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
          union all select 'a:'||a.attrelid::text||':'||a.attnum::text,coalesce(a.attacl::text,'')
           from pg_attribute a join pg_class c on c.oid=a.attrelid
           join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and a.attnum>0
           and a.attname<>'before_locked_at_start') s;"""
        before_acl=json.loads(run('psql.exe',connection+['-A','-t','-c',acl_sql],env))
        upgrade=root/'supabase/deploy/upgrade_owner_cleaning_checkpoints.sql'
        upgrade_sql=upgrade.read_text(encoding='utf-8')
        for migration in migrations[len(baseline):]:
            assert migration.read_text(encoding='utf-8') in upgrade_sql,'Rebuild the upgrade SQL bundle'
        execute('reviewed 046 -> 048 deployment bundle',path=upgrade)
        after_acl=json.loads(run('psql.exe',connection+['-A','-t','-c',acl_sql],env))
        assert all(after_acl.get(k)==v for k,v in before_acl.items()),'Existing public ACLs changed'
        execute('migration history',sql="""do $$ begin
          assert (select count(*) from supabase_migrations.schema_migrations
            where version in ('20261123000047','20261123000048'))=2;
        end $$;""")
        tests=['booking_start_time.sql','cleaning_evidence_checkpoints.sql']
        for test in tests:
            execute(test,path=root/'supabase/tests'/test)
        receipts.append({'profile':profile,'migrations':len(migrations),'tests':tests,'passed':True,
                         'existing_acl_entries_preserved':len(before_acl),
                         'hosted_services_tested':False,'workspace':str(workspace)})
        print('PASSED '+profile+': '+str(len(migrations))+' migrations and checkpoint regressions',flush=True)
    finally:
        if password_path.exists():password_path.unlink()
        if started:
            run('pg_ctl.exe',['-D',str(data),'-m','fast','-w','-t','30','stop'],env)
        (workspace/'verification.log').write_text(''.join(log),encoding='utf-8')
        env.pop('PGPASSWORD',None)
(args.output/'sql-receipt.json').write_text(json.dumps(receipts,indent=2),encoding='utf-8')
