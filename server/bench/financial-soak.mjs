import { createHash, randomBytes, randomUUID } from "node:crypto";
import pg from "pg";
const { Pool } = pg;
const durationSeconds = Number(process.env.SOAK_DURATION_SECONDS ?? 60);
const concurrency = Number(process.env.SOAK_WORKERS ?? 50);
const scenario = process.env.SOAK_SCENARIO ?? "hot";
const seed = String(process.env.SOAK_SEED ?? "mcias-ledger-soak-2026-11-02-v1");
const repeat = Number(process.env.SOAK_REPEAT ?? 1);
if (![60, 300].includes(durationSeconds)) throw new Error("SOAK_DURATION_SECONDS must be 60 or 300");
if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 50) throw new Error("SOAK_WORKERS must be 1..50");
if (!["hot", "uniform"].includes(scenario)) throw new Error("SOAK_SCENARIO must be hot or uniform");
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: concurrency + 2, idleTimeoutMillis: 10000, connectionTimeoutMillis: 10000, application_name: "ledger-financial-soak" });
const monitorPool = new Pool({ connectionString: process.env.DATABASE_URL, max: 2, application_name: "ledger-soak-monitor" });
function uuidFromMd5(value) { const h=createHash("md5").update(value).digest("hex"); return h.slice(0,8)+"-"+h.slice(8,12)+"-"+h.slice(12,16)+"-"+h.slice(16,20)+"-"+h.slice(20); }
function percentile(sorted,p) { return sorted.length ? Number(sorted[Math.min(sorted.length-1,Math.floor((sorted.length-1)*p))].toFixed(2)) : null; }
function summarize(values) { const sorted=[...values].sort((a,b)=>a-b); return {count:sorted.length,p50:percentile(sorted,.5),p95:percentile(sorted,.95),p99:percentile(sorted,.99),max:sorted.length?Number(sorted.at(-1).toFixed(2)):null}; }
function delta(after,before) { const out={}; for(const k of Object.keys(after)) out[k]=Number(after[k]??0)-Number(before[k]??0); return out; }
const relationships=Array.from({length:1000},(_,i)=>({id:uuidFromMd5("bench-rel-"+(i+1)),seller:uuidFromMd5("bench-user-"+(i+1)+"-1"),buyer:uuidFromMd5("bench-user-"+(i+1)+"-2"),device:uuidFromMd5("bench-device-profile-"+(i+1))}));
const hotRelationship=relationships[0];
const stageSamples=Object.create(null);
function recordStage(name,ms){(stageSamples[name]??=[]).push(ms);}
async function timed(name,action){const t=process.hrtime.bigint();try{return await action();}finally{recordStage(name,Number(process.hrtime.bigint()-t)/1e6);}}
async function createApprovedOperation(rel,type,actor,approver,payload){
 const id=randomUUID();
 await timed("accept_"+type,()=>pool.query("SELECT * FROM ledger.accept_operation($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::bytea,$7::jsonb,0,1,now())",[id,rel.id,actor,rel.device,type,randomBytes(32),JSON.stringify(payload)]));
 await timed("approve_"+type+"_and_post",()=>pool.query("SELECT ledger.decide_operation($1::uuid,$2::uuid,$3::uuid,$4::uuid,1,'approved','financial soak')",[randomUUID(),rel.id,id,approver]));
 return id;
}
async function snapshot(){
 const [wal,db]=await Promise.all([
  monitorPool.query("SELECT wal_records,wal_fpi,wal_bytes,wal_buffers_full FROM pg_stat_wal"),
  monitorPool.query("SELECT xact_commit,blks_hit,blks_read,tup_inserted,tup_updated,deadlocks,temp_bytes FROM pg_stat_database WHERE datname=current_database()")
 ]);
 let statements=null,error=null;
 try{const r=await monitorPool.query("SELECT queryid::text AS queryid,calls,total_exec_time,mean_exec_time,rows,shared_blks_hit,shared_blks_read,temp_blks_written FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 100");statements=r.rows;}catch(e){error=String(e);}
 return {wal:wal.rows[0],database:db.rows[0],statements,statementsError:error};
}
const seedOffset=Number.parseInt(createHash("sha256").update(seed).digest("hex").slice(0,6),16);
function chooseRelationship(worker,iteration){
 if(scenario==="hot"){const bucket=(worker*37+iteration*17+seedOffset)%100;if(bucket<90)return hotRelationship;return relationships[1+((worker*19+iteration*13)%(relationships.length-1))];}
 return relationships[(worker*23+iteration*7+seedOffset)%relationships.length];
}
async function main(){
 const env=await monitorPool.query("SELECT version() AS version,current_setting('shared_buffers') AS shared_buffers,current_setting('max_connections') AS max_connections");
 const ext=await monitorPool.query("SELECT extname FROM pg_extension WHERE extname='pg_stat_statements'");
 const metadata={benchmark:"financial_lifecycle_soak",seed,repeat,scenario,hotRelationshipId:scenario==="hot"?hotRelationship.id:null,hotShareTargetPercent:scenario==="hot"?90:0,concurrency,targetDurationSeconds:durationSeconds,environment:env.rows[0],pgStatStatementsEnabled:ext.rowCount===1};
 console.log("SOAK_METADATA "+JSON.stringify(metadata));
 const before=await snapshot(),waitSamples=Object.create(null),lockSamples=Object.create(null),activitySamples=[];
 let stop=false;
 const monitor=(async()=>{while(!stop){try{
  const [waits,locks,activity]=await Promise.all([
   monitorPool.query("SELECT COALESCE(wait_event_type,'CPU_or_running') AS wait_type,COALESCE(wait_event,'none') AS wait_event,state,count(*)::int AS sessions FROM pg_stat_activity WHERE application_name='ledger-financial-soak' AND state='active' GROUP BY 1,2,3"),
   monitorPool.query("SELECT l.locktype,l.mode,l.granted,count(*)::int AS lock_count FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='ledger-financial-soak' GROUP BY l.locktype,l.mode,l.granted"),
   monitorPool.query("SELECT state,wait_event_type,wait_event,count(*)::int AS sessions,max(clock_timestamp()-query_start) AS longest_query_age FROM pg_stat_activity WHERE application_name='ledger-financial-soak' GROUP BY state,wait_event_type,wait_event")
  ]);
  for(const x of waits.rows){const k=[x.wait_type,x.wait_event,x.state].join("|");waitSamples[k]=(waitSamples[k]??0)+x.sessions;}
  for(const x of locks.rows){const k=[x.locktype,x.mode,x.granted].join("|");lockSamples[k]=(lockSamples[k]??0)+x.lock_count;}
  activitySamples.push({at:new Date().toISOString(),groups:activity.rows});
 }catch(e){process.stderr.write("monitor sample failed: "+String(e)+"\n");}await new Promise(r=>setTimeout(r,500));}})();
 const start=Date.now(),deadline=start+durationSeconds*1000;let completed=0,errors=0;const latency=[],errorSamples=[];
 await Promise.all(Array.from({length:concurrency},async(_,worker)=>{let i=0;while(Date.now()<deadline){const rel=chooseRelationship(worker,i++),t=process.hrtime.bigint();try{
  const amountMinor=1000;
  const charge=await createApprovedOperation(rel,"credit_charge",rel.seller,rel.buyer,{creditorUserId:rel.seller,debtorUserId:rel.buyer,currency:"YER",amountMinor});
  const obligation=await timed("lookup_obligation_id",()=>pool.query("SELECT id FROM ledger.obligations WHERE source_operation_id=$1::uuid",[charge]));
  if(!obligation.rows[0])throw new Error("approved charge did not create obligation");
  const paymentId=await createApprovedOperation(rel,"payment",rel.buyer,rel.seller,{payerUserId:rel.buyer,payeeUserId:rel.seller,currency:"YER",amountMinor});
  const payment=await timed("lookup_payment_id",()=>pool.query("SELECT id FROM ledger.payments WHERE source_operation_id=$1::uuid",[paymentId]));
  if(!payment.rows[0])throw new Error("approved payment did not create payment");
  await createApprovedOperation(rel,"allocation",rel.buyer,rel.seller,{paymentId:payment.rows[0].id,obligationId:obligation.rows[0].id,amountMinor});completed++;
 }catch(e){errors++;if(errorSamples.length<20)errorSamples.push(String(e));}finally{latency.push(Number(process.hrtime.bigint()-t)/1e6);}}}));
 stop=true;await monitor;
 const after=await snapshot(),actualDurationMs=Date.now()-start,statementDeltas=[];
 if(before.statements&&after.statements){const old=new Map(before.statements.map(x=>[x.queryid,x]));for(const x of after.statements){const b=old.get(x.queryid)||{};statementDeltas.push({queryid:x.queryid,calls:Number(x.calls)-Number(b.calls??0),totalExecTimeMs:Number(x.total_exec_time)-Number(b.total_exec_time??0),rows:Number(x.rows)-Number(b.rows??0),sharedBlksRead:Number(x.shared_blks_read)-Number(b.shared_blks_read??0),sharedBlksHit:Number(x.shared_blks_hit)-Number(b.shared_blks_hit??0),tempBlksWritten:Number(x.temp_blks_written)-Number(b.temp_blks_written??0)});}statementDeltas.sort((a,b)=>b.totalExecTimeMs-a.totalExecTimeMs);}
 const report={...metadata,actualDurationMs,completedLifecycles:completed,errors,errorSamples,throughputPerSecond:Number((completed/(actualDurationMs/1000)).toFixed(3)),fullLifecycleLatencyMs:summarize(latency),stageLatencyMs:Object.fromEntries(Object.entries(stageSamples).map(([k,v])=>[k,summarize(v)])),sampledWaitEvents:waitSamples,sampledLocks:lockSamples,sampledActivity:activitySamples,walDelta:delta(after.wal,before.wal),databaseDelta:delta(after.database,before.database),pgStatStatementsError:after.statementsError,topStatementDeltas:statementDeltas.slice(0,25)};
 console.log("SOAK_RESULT "+JSON.stringify(report));if(errors)throw new Error("soak run had "+errors+" failed lifecycles");
}
try{await main();}finally{await Promise.all([pool.end(),monitorPool.end()]);}
