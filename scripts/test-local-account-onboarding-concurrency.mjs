import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {execFileSync, spawn} from 'node:child_process';
import {realpathSync} from 'node:fs';

assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const container='supabase_db_ledger_target_supabase_local';
const docker=args=>execFileSync('docker',args,{encoding:'utf8',timeout:15000});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])),/^unix:\/\//);
const labels=JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
assert.equal(labels['com.supabase.cli.project'],'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
const args=['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'];
const sql=input=>execFileSync('docker',args,{input,encoding:'utf8',timeout:15000}).trim();
const q=value=>"'"+value.replaceAll("'","''")+"'";
const children=[];
function session() {
  const child=spawn('docker',args,{stdio:['pipe','pipe','pipe']}); children.push(child);
  let out='',err=''; child.stdout.on('data',b=>out+=b); child.stderr.on('data',b=>err+=b);
  const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>resolve({code,out:out.trim(),err}));});
  done.catch(()=>{});
  return {child,done,output:()=>out};
}
async function waitFor(condition) {
  const deadline=Date.now()+10000;
  while(!condition()) {assert.ok(Date.now()<deadline,'Database lock not observed');await new Promise(r=>setTimeout(r,50));}
}
const users=[];
let uiDevice;
const native=process.argv.includes('--native');
const signOutUI=process.argv.includes('--ui-signout');
const ui=process.argv.includes('--ui')||signOutUI;
assert.deepEqual(process.argv.slice(2),signOutUI?['--ui-signout']:ui?['--ui']:native?['--native']:[]);
try {
  for(const sameKey of native||ui?[]:[true,false]) {
    const user=randomUUID(), principal=randomUUID(), key=randomUUID(); users.push(user);
    sql(`insert into auth.users(id,aud,role,email,encrypted_password) values(${q(user)},'authenticated','authenticated',${q(user+'@ledger-tests.invalid')},'');
      insert into public.spike_principals(id,auth_user_id) values(${q(principal)},${q(user)});`);
    for(const isolation of ['repeatable read','serializable']) {
      const rejected=session();
      rejected.child.stdin.end(`begin isolation level ${isolation}; set local role authenticated;
        set local request.jwt.claims=${q(JSON.stringify({sub:user,role:'authenticated',is_anonymous:false}))};
        select public.spike_create_initial_account(${q(key)},'My account'); commit;`);
      const result=await rejected.done;
      assert.notEqual(result.code,0);
      assert.match(result.err,/Account creation requires READ COMMITTED/);
      assert.equal(sql(`select count(*) from ledger_private.account_creation_receipts where auth_user_id=${q(user)}`),'0');
    }
    const blocker=session();
    blocker.child.stdin.write(`begin; select id from public.spike_principals where id=${q(principal)} for update;\n\\echo LOCKED\n`);
    await waitFor(()=>blocker.output().includes('LOCKED'));
    const run=(name,request)=>{
      const peer=session();
      peer.child.stdin.end(`set application_name=${q(name)};set role authenticated;
        set request.jwt.claims=${q(JSON.stringify({sub:user,role:'authenticated',is_anonymous:false}))};
        select public.spike_create_initial_account(${q(request)},'My account')->>'accountId';`);
      return peer.done;
    };
    const aName='onboard-a-'+user,bName='onboard-b-'+user;
    const a=run(aName,key),b=run(bName,sameKey?key:randomUUID());
    await waitFor(()=>sql(`select count(*) from pg_stat_activity where application_name in (${q(aName)},${q(bName)}) and wait_event_type='Lock'`)==='2');
    blocker.child.stdin.end('commit;\n');assert.equal((await blocker.done).code,0);
    const results=await Promise.all([a,b]);
    if(sameKey) {assert.ok(results.every(r=>r.code===0),JSON.stringify(results));assert.equal(results[0].out,results[1].out);}
    else {assert.equal(results.filter(r=>r.code===0).length,1);assert.match(results.find(r=>r.code!==0).err,/account_already_available/);}
    assert.equal(sql(`select count(*) from public.spike_account_memberships where principal_id=${q(principal)} and state='active'`),'1');
    assert.equal(sql(`select count(*) from ledger_private.account_creation_receipts where auth_user_id=${q(user)}`),'1');
    assert.equal(sql(`select count(*) from public.spike_budget_categories c join public.spike_account_memberships m on m.account_id=c.account_id where m.principal_id=${q(principal)}`),'4');
  }
  if(native||ui) {
    const status=JSON.parse(execFileSync('npx',['--yes','supabase@2.116.0','status','-o','json'],
      {encoding:'utf8',stdio:['ignore','pipe','ignore']}));
    assert.equal(status.API_URL,'http://127.0.0.1:54321');
    const email=randomUUID()+'@ledger-tests.invalid',password=randomUUID()+randomUUID();
    const response=await fetch(status.API_URL+'/auth/v1/admin/users',{
      method:'POST',headers:{apikey:status.PUBLISHABLE_KEY,Authorization:'Bearer '+status.SERVICE_ROLE_KEY,
        'Content-Type':'application/json'},body:JSON.stringify({email,password,email_confirm:true})});
    assert.equal(response.status,200,'Local synthetic user creation failed');
    const user=await response.json();assert.match(user.id,/^[0-9a-f-]{36}$/);users.push(user.id);
    if(ui) {
      const testMethod=signOutUI?'testLocalEmptyAccountSignOutSurvivesRelaunch':'testLocalAccountOnboardingThroughExistingGate';
      const sim=args=>execFileSync('xcrun',['simctl',...args],{encoding:'utf8'}).trim();
      const type=JSON.parse(sim(['list','devicetypes','-j'])).devicetypes.find(x=>x.name==='iPhone 17 Pro');
      const runtime=JSON.parse(sim(['list','runtimes','-j'])).runtimes.find(x=>x.name==='iOS 26.5'&&x.isAvailable);
      assert.ok(type&&runtime,'Required local simulator runtime unavailable');
      uiDevice=sim(['create','Ledger Onboarding QA '+randomUUID(),type.identifier,runtime.identifier]);
      assert.match(uiDevice,/^[0-9A-F-]{36}$/i);
      sim(['boot',uiDevice]);
      let output;
      try { output=execFileSync('xcodebuild',['-project','LedgeriOS/LedgerTarget.xcodeproj',
        '-scheme','LedgerTargetStaging','-configuration','Debug',
        '-destination','platform=iOS Simulator,id='+uiDevice,
        'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','LEDGER_TARGET_COMPILATION_CONDITIONS=LEDGER_TARGET_LOCAL',
        'LEDGER_LOCAL_PUBLISHABLE_KEY='+status.PUBLISHABLE_KEY,'-parallel-testing-enabled','NO',
        '-only-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests/'+testMethod,
        '-resultBundlePath','/tmp/ledger-onboarding-ui-'+randomUUID()+'.xcresult','test'],{
        encoding:'utf8',timeout:300000,maxBuffer:32*1024*1024,env:{...process.env,
          TEST_RUNNER_LEDGER_ONBOARDING_UI:'1',TEST_RUNNER_LEDGER_ONBOARDING_EMAIL:email,
          TEST_RUNNER_LEDGER_ONBOARDING_PASSWORD:password}}); }
      catch(error) {
        process.stdout.write(error.stdout??'');process.stderr.write(error.stderr??'');
        throw Error('Local onboarding UI failed; see captured Xcode output and result bundle');
      }
      assert.match(output,new RegExp(testMethod+'.*passed'));
      process.stdout.write(output);
    } else {
    const output=execFileSync('swift',['test','--package-path','LedgeriOS','--no-parallel',
      '--filter','AccountWorkspacePendingWorkRuntimeTests/localAccountOnboarding'],{
      encoding:'utf8',timeout:180000,maxBuffer:16*1024*1024,env:{...process.env,
        LEDGER_ONBOARDING_LOCAL:'1',LEDGER_ONBOARDING_EMAIL:email,
        LEDGER_ONBOARDING_PASSWORD:password,LEDGER_ONBOARDING_KEY:status.PUBLISHABLE_KEY}});
    process.stdout.write(output);
    }
  } else {
    console.log('PASS: unsupported isolation rejected without writes; concurrent same-key replay and different-key creation each produce one Account, one receipt, four categories.');
  }
} finally {
  for(const child of children) if(child.exitCode===null) child.kill();
  if(uiDevice) {
    execFileSync('xcrun',['simctl','shutdown',uiDevice],{stdio:'ignore'});
    execFileSync('xcrun',['simctl','delete',uiDevice],{stdio:'ignore'});
  }
  // Only identities created by this invocation and their new Accounts.
  for(const user of users) sql(`begin;
    create temporary table onboarding_cleanup_accounts on commit drop as select account_id from ledger_private.account_creation_receipts where auth_user_id=${q(user)};
    delete from ledger_private.account_creation_receipts where auth_user_id=${q(user)};
    delete from public.spike_accounts where id in(select account_id from onboarding_cleanup_accounts);
    delete from auth.users where id=${q(user)};commit;`);
}
