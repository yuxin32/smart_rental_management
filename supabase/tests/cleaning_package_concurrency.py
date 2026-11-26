"""Concurrent psql sessions against only the disposable database owned by the runner."""
from concurrent.futures import ThreadPoolExecutor
import json
import time


def verify(run, connection, env, root, log):
    owner='53000000-0000-4000-8000-000000000001'
    provider='53000000-0000-4000-8000-000000000002'
    service='53000000-0000-4000-8000-000000000010'
    fixture=(root/'supabase/tests/cleaning_packages.sql').read_text(encoding='utf-8').split('-- Ensure privilege defaults')[0]
    fixture+=f"""
      set local role authenticated;
      select set_config('request.jwt.claim.sub','{provider}',true);
      select public.save_my_cleaning_package('{service}',120,2,100,'Original scope',true,0);
      commit;
    """
    run('psql.exe',connection,env,fixture)

    def execute(sql, name='package-probe'):
        return run('psql.exe',connection+['-A','-t'],dict(env,PGAPPNAME=name),sql).strip()

    package_id=execute(f"select package_id from app_private.cleaning_package where provider_id='{provider}';")
    start="((((now() at time zone 'Asia/Kuala_Lumpur')::date+7)+time '10:00') at time zone 'Asia/Kuala_Lumpur')"

    def wait_for(sql, message):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            if execute(sql)=='t':return
            time.sleep(.03)
        raise AssertionError(message)

    def save(revision, scope, enabled=True):
        return f"""set local role authenticated;
          select set_config('request.jwt.claim.sub','{provider}',true);
          select public.save_my_cleaning_package('{service}',120,2,100,'{scope}',{str(enabled).lower()},{revision},'{package_id}');"""

    def attempt(revision):
        return f"""set role authenticated;
          select set_config('request.jwt.claim.sub','{owner}',false);
          select public.create_pending_package_booking(gen_random_uuid(),'{provider}',
           '53000000-0000-4000-8000-000000000020','{service}',{start},{start}+interval '2 hours',
           '{package_id}',100,{revision});"""

    results=[]
    # Each owner request must demonstrably wait on the provider row, then read
    # the newly committed package rather than its stale search-time version.
    with ThreadPoolExecutor(max_workers=2) as pool:
        for revision,scope,enabled,reason in [(1,'Changed same-price scope',True,'package_changed'),
                                              (2,'Paused while submitting',False,'package_unavailable')]:
            editor_name=f'package-editor-{revision}'
            owner_name=f'package-owner-{revision}'
            editor=pool.submit(execute,'begin;'+save(revision,scope,enabled)+'select pg_sleep(3);commit;',editor_name)
            wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{editor_name}' and wait_event='PgSleep');",
                     'Editor never acquired the provider/package locks')
            booking=pool.submit(execute,attempt(revision),owner_name)
            wait_for(f"select exists(select 1 from pg_stat_activity where application_name='{owner_name}' and cardinality(pg_blocking_pids(pid))>0);",
                     'Booking bypassed the provider lock during a package edit')
            editor.result(timeout=10)
            response=json.loads(booking.result(timeout=10).splitlines()[-1])
            assert response=={'created':False,'reason':reason},response
            assert execute('select count(*) from public.booking;')=='0','Stale package booking escaped'
            results.append({'case':reason,'provider_lock_observed':True,'created':False})

        # Competing own-package writes carry the same revision. Exactly one may
        # commit; the other must report conflict after obtaining the row lock.
        def competing(scope):
            try:
                result=execute('begin;'+save(3,scope)+'commit;',scope)
                return json.loads(next(line for line in result.splitlines() if line.startswith('{')))
            except RuntimeError as error:
                assert 'Package changed; reload before saving' in str(error),str(error)
                return 'stale'
        futures=[pool.submit(competing,'Writer one'),pool.submit(competing,'Writer two')]
        outcomes=[future.result(timeout=10) for future in futures]
        assert sum(isinstance(x,dict) for x in outcomes)==1,outcomes
        assert outcomes.count('stale')==1,outcomes
        assert execute(f"select revision from app_private.cleaning_package where package_id='{package_id}';")=='4'
        results.append({'case':'concurrent_package_edits','committed':1,'stale':1})
    log.append('CONCURRENCY '+json.dumps(results)+'\n')
    return results
