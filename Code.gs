// ── Smash Ladder — Google Sheets backend (Apps Script) ──────────────────
// Setup:
// 1. Open your empty Google Sheet.
// 2. Extensions > Apps Script.
// 3. Delete any boilerplate, paste this whole file in.
// 4. CHANGE AUTH_USER / AUTH_PASS below to your own values.
// 5. Click Deploy > New deployment > type "Web app".
//    - Execute as: Me
//    - Who has access: Anyone
// 6. Authorize when prompted (first time only).
// 7. Copy the Web App URL it gives you and paste it into the app's Settings tab.
//    The app will then prompt for the username/password you set below.
// The four tabs (Players/Sessions/Courts/Games) are created automatically on first call.

const AUTH_USER='admin';
const AUTH_PASS='change-me';

const PLAYERS_SHEET='Players';
const SESSIONS_SHEET='Sessions';
const COURTS_SHEET='Courts';
const GAMES_SHEET='Games';

function checkAuth_(u,p){
  return u===AUTH_USER && p===AUTH_PASS;
}

function doGet(e){
  if(!checkAuth_(e.parameter.u,e.parameter.p))return jsonOut_({error:'unauthorized'});
  return jsonOut_(loadState_());
}

function doPost(e){
  const body=JSON.parse(e.postData.contents);
  const auth=body.auth||{};
  if(!checkAuth_(auth.u,auth.p))return jsonOut_({error:'unauthorized'});
  saveState_(body.data);
  return jsonOut_({ok:true});
}

function jsonOut_(obj){
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function ensureSheets_(){
  const ss=SpreadsheetApp.getActiveSpreadsheet();
  const defs={
    [PLAYERS_SHEET]:['id','name','rank','totalPts','wins','losses','sessions','rankDelta'],
    [SESSIONS_SHEET]:['sessionId','date','numCourts','numRounds','rankBasis','round','status','skipped','attending','bands','rankChanges'],
    [COURTS_SHEET]:['sessionId','round','courtIndex','players','maxScore'],
    [GAMES_SHEET]:['sessionId','round','courtIndex','gameIndex','pair1','pair2','sitOut','s1','s2']
  };
  Object.keys(defs).forEach(name=>{
    let sh=ss.getSheetByName(name);
    if(!sh)sh=ss.insertSheet(name);
    if(sh.getRange(1,1).getValue()!==defs[name][0]){
      sh.clear();
      sh.getRange(1,1,1,defs[name].length).setValues([defs[name]]);
    }
  });
  return ss;
}

function readRows_(ss,name){
  const sh=ss.getSheetByName(name);
  const vals=sh.getDataRange().getValues();
  if(vals.length<2)return[];
  const headers=vals[0];
  return vals.slice(1).filter(row=>row.some(v=>v!==''))
    .map(row=>{const obj={};headers.forEach((h,i)=>obj[h]=row[i]);return obj;});
}

function writeRows_(ss,name,rows){
  const sh=ss.getSheetByName(name);
  const lastRow=sh.getMaxRows();
  if(lastRow>1)sh.getRange(2,1,lastRow-1,sh.getMaxColumns()).clearContent();
  if(!rows.length)return;
  sh.getRange(2,1,rows.length,rows[0].length).setValues(rows);
}

function loadState_(){
  const ss=ensureSheets_();
  const players=readRows_(ss,PLAYERS_SHEET).map(r=>({
    id:Number(r.id),name:r.name,rank:Number(r.rank),totalPts:Number(r.totalPts)||0,
    wins:Number(r.wins)||0,losses:Number(r.losses)||0,sessions:Number(r.sessions)||0,rankDelta:Number(r.rankDelta)||0
  }));
  const sessionRows=readRows_(ss,SESSIONS_SHEET);
  const courtRows=readRows_(ss,COURTS_SHEET);
  const gameRows=readRows_(ss,GAMES_SHEET);

  function buildSession(sr){
    const sid=sr.sessionId;
    const cRows=courtRows.filter(c=>c.sessionId===sid);
    const maxRound=cRows.reduce((m,c)=>Math.max(m,Number(c.round)),0);
    const rounds=[];
    for(let rnd=1;rnd<=maxRound;rnd++){
      const thisCourts=cRows.filter(c=>Number(c.round)===rnd).sort((a,b)=>Number(a.courtIndex)-Number(b.courtIndex));
      const courts=thisCourts.map(c=>{
        const courtPlayers=JSON.parse(c.players||'[]');
        const games=gameRows.filter(g=>g.sessionId===sid&&Number(g.round)===rnd&&Number(g.courtIndex)===Number(c.courtIndex))
          .sort((a,b)=>Number(a.gameIndex)-Number(b.gameIndex))
          .map(g=>({pair1:JSON.parse(g.pair1),pair2:JSON.parse(g.pair2),sitOut:g.sitOut===''?null:Number(g.sitOut),s1:g.s1===''?null:Number(g.s1),s2:g.s2===''?null:Number(g.s2)}));
        return{players:courtPlayers,games,maxScore:Number(c.maxScore)||21};
      });
      rounds.push({courts});
    }
    const isActive=sr.status==='active';
    const obj={
      date:sr.date,
      numRounds:Number(sr.numRounds),
      rankBasis:sr.rankBasis,
      round:Number(sr.round),
      bands:JSON.parse(sr.bands||'[]'),
      skipped:JSON.parse(sr.skipped||'[]'),
      attending:JSON.parse(sr.attending||'[]')
    };
    if(isActive){
      obj.courts=rounds.length?rounds[rounds.length-1].courts:[];
      obj.rounds=rounds.slice(0,-1);
    }else{
      obj.rounds=rounds;
      obj.rankChanges=JSON.parse(sr.rankChanges||'null');
    }
    return obj;
  }

  const activeRow=sessionRows.find(s=>s.status==='active');
  const activeSession=activeRow?buildSession(activeRow):null;
  const sessions=sessionRows.filter(s=>s.status==='finalized').map(buildSession);
  const nextId=players.reduce((m,p)=>Math.max(m,p.id),0)+1;

  return{players,nextId,activeSession,sessions};
}

function saveState_(S){
  const ss=ensureSheets_();
  const playerRows=(S.players||[]).map(p=>[p.id,p.name,p.rank,p.totalPts||0,p.wins||0,p.losses||0,p.sessions||0,p.rankDelta||0]);
  writeRows_(ss,PLAYERS_SHEET,playerRows);

  const sessionRows=[],courtRows=[],gameRows=[];
  let sidCounter=1;

  function flatten(s,status){
    const sid=sidCounter++;
    const roundsArr=status==='active'?[...(s.rounds||[]),{courts:s.courts||[]}]:(s.rounds||[]);
    sessionRows.push([sid,s.date,(s.bands||[]).length,s.numRounds,s.rankBasis,s.round,status,
      JSON.stringify(s.skipped||[]),JSON.stringify(s.attending||[]),JSON.stringify(s.bands||[]),
      JSON.stringify(s.rankChanges||null)]);
    roundsArr.forEach((r,ri)=>{
      (r.courts||[]).forEach((c,ci)=>{
        courtRows.push([sid,ri+1,ci,JSON.stringify(c.players||[]),c.maxScore||21]);
        (c.games||[]).forEach((g,gi)=>{
          gameRows.push([sid,ri+1,ci,gi,JSON.stringify(g.pair1||[]),JSON.stringify(g.pair2||[]),g.sitOut===null||g.sitOut===undefined?'':g.sitOut,g.s1===null?'':g.s1,g.s2===null?'':g.s2]);
        });
      });
    });
  }

  if(S.activeSession)flatten(S.activeSession,'active');
  (S.sessions||[]).forEach(s=>flatten(s,'finalized'));

  writeRows_(ss,SESSIONS_SHEET,sessionRows);
  writeRows_(ss,COURTS_SHEET,courtRows);
  writeRows_(ss,GAMES_SHEET,gameRows);
}
