const fs=require('fs'),path=require('path');const root=process.argv[2];if(!root)throw Error('Private migration directory required');const load=n=>JSON.parse(fs.readFileSync(path.join(root,n+'.json'),'utf8'));const mine=load('mine'),wanting=load('wanting'),target=load('target');const validation=load('evidence-validation-export')[0].payload;const evidence=typeof validation==='string'?JSON.parse(validation):validation;
if(target.tables['auth.users'].length||target.tables['public.user_account'].length)throw Error('Target contains accounts; reconcile before migration');
const auth=[...mine.tables['auth.users'],...wanting.tables['auth.users']];if(new Set(auth.map(x=>x.email.toLowerCase())).size!==auth.length)throw Error('Duplicate email reconciliation required');if(new Set(auth.map(x=>x.id)).size!==auth.length)throw Error('Duplicate user UUID reconciliation required');
const remap=new Map(wanting.tables['public.service_type'].map(s=>[s.service_type_id,target.tables['public.service_type'].find(t=>t.name===s.name)?.service_type_id]));if([...remap.values()].some(v=>!v))throw Error('Service catalogue requires reconciliation');
const staged={};for(const [source,data]of [['mine',mine],['wanting',wanting]])for(const [name,records]of Object.entries(data.tables)){if(name.startsWith('storage.')||['public.app_deployment_environment','public.service_type'].includes(name)||!records.length)continue;let rows=structuredClone(records);if(source==='wanting'){let text=JSON.stringify(rows);for(const [oldId,newId]of remap)text=text.replaceAll(oldId,newId);rows=JSON.parse(text);}for(const r of rows){if(name==='public.user_account'){r.role=r.role??r.account_type;r.contact_number=r.contact_number??r.phone??null;r.full_name=r.full_name??r.display_name??'';r.account_status=r.account_status??'active';delete r.account_type;delete r.phone;delete r.display_name;}if(name==='public.tenant_registration'){r.contact_number=r.contact_number??r.phone;delete r.phone;}if(name==='public.provider_profile'){r.full_name=r.full_name??r.display_name??null;delete r.display_name;}if(name==='public.property')r.legacy_source_project='gqtetdavmrautoojaqrk';if(name==='auth.users'){const meta=r.raw_user_meta_data;if(meta?.requested_display_name){meta.requested_full_name=meta.requested_display_name;delete meta.requested_display_name;}for(const field of ['confirmation_token','recovery_token','email_change_token_new','email_change_token_current','reauthentication_token'])if(field in r)r[field]='';for(const field of ['confirmation_sent_at','recovery_sent_at','email_change_sent_at','reauthentication_sent_at'])if(field in r)r[field]=null;}}
(staged[name]??=[]).push(...rows);}
if(evidence.length)staged['app_private.evidence_validation']=evidence;
const q=s=>"'"+String(s).replaceAll("'","''")+"'";
const exclude=new Set(target.columns.filter(c=>c.is_generated==='ALWAYS').map(c=>c.table_schema+'.'+c.table_name+'.'+c.column_name));
for(const [name,rows]of Object.entries(staged))for(const row of rows)for(const col of Object.keys(row))if(exclude.has(name+'.'+col))delete row[col];
let sql='begin;\n';sql+=`do $$ begin if exists(select 1 from public.user_account) or exists(select 1 from auth.users) then raise exception 'Target is no longer empty. Migration aborted.';end if;end $$;\n`;
sql+=fs.readFileSync('supabase/migrations/20261123000046_legacy_property_and_evidence_compatibility.sql','utf8')+'\n';
sql+=`create temporary table migration_stage(name text primary key, payload jsonb, done boolean not null default false) on commit drop;\n`;
for(const [name,rows]of Object.entries(staged))sql+=`insert into migration_stage(name,payload) values(${q(name)},${q(JSON.stringify(rows))}::jsonb);\n`;
sql+=`do $$ declare r record; begin for r in select name from migration_stage where name like 'public.%' or name like 'app_private.%' loop execute format('alter table %s disable trigger user',r.name::regclass);end loop;end $$;\n`;
sql+=`do $$ declare r record; cols text; progress boolean; item jsonb; begin
while exists(select 1 from migration_stage where not done) loop
 progress:=false;
 for r in select s.* from migration_stage s where not s.done and not exists(
 select 1 from pg_constraint c join migration_stage dep on c.confrelid=dep.name::regclass
 where c.conrelid=s.name::regclass and c.contype='f' and not dep.done and dep.name<>s.name
 ) order by s.name loop
 for item in select value from jsonb_array_elements(r.payload) loop
 select string_agg(format('%I',key),',') into cols from jsonb_object_keys(item) key;
 execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s,$1)',r.name::regclass,cols,cols,r.name::regclass) using item;
 end loop;
 update migration_stage set done=true where name=r.name;progress:=true;
 end loop;
 if not progress then raise exception 'Unresolved foreign key cycle in staged migration'; end if;
end loop;
end $$;\n`;
sql+=`do $$ declare r record; actual bigint; begin for r in select * from migration_stage loop execute format('select count(*) from %s',r.name::regclass) into actual; if actual<>jsonb_array_length(r.payload) then raise exception 'Row count mismatch for %',r.name;end if;end loop;end $$;\n`;
sql+=`do $$ declare r record;begin for r in select name from migration_stage where name like 'public.%' or name like 'app_private.%' loop execute format('alter table %s enable trigger user',r.name::regclass);end loop;end $$;\n`;
sql+=`select name,jsonb_array_length(payload) as migrated_rows from migration_stage order by name;\ncommit;\n`;
fs.writeFileSync(path.join(root,'import-data.sql'),sql);fs.writeFileSync(path.join(root,'normalized-staging.json'),JSON.stringify(staged));console.log('Prepared transactional import',Object.fromEntries(Object.entries(staged).map(([k,v])=>[k,v.length])));console.log('Mapped service types by name:',remap.size,'Private SQL bytes:',sql.length);

