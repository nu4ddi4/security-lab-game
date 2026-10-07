// Capture independent v0.7.0 oracle states for the native engine.
import fs from 'node:fs';
import {initialState,inspectDevice,applyAnswer,applyPort,applyLogin,restoreFile,runCommand,nextMission,score,stage,worldAction,missionId,progress,equipmentStatus} from '../src/engine.js';
import {encodeGame,exportGame} from '../src/storage.js';
const state=initialState(),steps=[];
async function record(action,...args){
 const calls={inspect:inspectDevice,answer:applyAnswer,port:applyPort,login:applyLogin,restore:restoreFile,command:runCommand,next:nextMission};
 await calls[action](state,...args);
 steps.push(structuredClone({action,args,expected:{mission:missionId(state),score:score(state),stage:stage(state),verified:progress(state).verified,clues:[...progress(state).clues],ports:{...state.ports},login:{...state.login},hashes:progress(state).hashes.map(({name,actual,expected,matches})=>({name,actual,expected,matches})),spatial:progress(state).spatial??null,mode:worldAction(state).mode}}));
}
await record('command','scan 127.0.0.1');
await record('inspect','INTERACT_AdminPC');
await record('answer',1);await record('command','verify');
await record('answer',0);await record('command','verify');
await record('next');
await record('inspect','INTERACT_ServerRack');await record('answer',1);
await record('port',443,false);await record('port',8080,false);
await record('inspect','INTERACT_ServerRack');await record('command','verify');
await record('port',443,true);await record('command','scan club-server');await record('command','verify');
await record('inspect','INTERACT_ServerRack');await record('command','verify');
await record('next');
await record('inspect','INTERACT_AdminPC');await record('answer',2);
await record('login',{minLength:12,blockCommon:true,limitAttempts:false});await record('inspect','INTERACT_AdminPC');await record('command','verify');
await record('login',{minLength:15,blockCommon:true,limitAttempts:true});await record('command','inspect login');await record('command','verify');
await record('inspect','INTERACT_AdminPC');await record('command','verify');
await record('next');
await record('inspect','INTERACT_FileCabinet');await record('inspect','INTERACT_AdminPC');await record('answer',1);
await record('restore','notice.txt');await record('inspect','INTERACT_AdminPC');await record('command','verify');
await record('restore','budget.csv');await record('command','verify');
await record('command','hash files');await record('command','verify');
await record('inspect','INTERACT_AdminPC');await record('command','verify');
fs.writeFileSync('godot/tests/parity.json',JSON.stringify({baseline:'v0.7.0',steps},null,2)+'\n');
fs.writeFileSync('godot/tests/web-export.json',exportGame(state)+'\n');
fs.writeFileSync('godot/tests/web-legacy.json',JSON.stringify(encodeGame(state,{legacy:true}),null,2)+'\n');
console.log(`${steps.length} independently derived engine checkpoints`);
