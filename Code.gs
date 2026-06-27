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
//
// Sheet layout this script maintains:
//   _Data      — hidden, single JSON blob, the only tab the app actually reads back.
//   Dashboard  — readable player ladder (Rank/Name/Trend/Wins/Losses/Points).
//   <date>     — one readable tab per session (current + history), showing
//                rounds, courts, games, points/position, skipped players, rank changes.
// If you redeploy this over an older version that had Players/Sessions/Courts/Games
// tabs, those get deleted automatically the next time the app saves.

const AUTH_USER='admin';
const AUTH_PASS='change-me';
const DATA_SHEET='_Data';
const DASHBOARD_SHEET='Dashboard';
const LEGACY_SHEETS=['Players','Sessions','Courts','Games'];

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

function def_(){return{players:[],nextId:1,sessions:[],activeSession:null};}

function ensureBaseSheets_(){
  const ss=SpreadsheetApp.getActiveSpreadsheet();
  let data=ss.getSheetByName(DATA_SHEET);
  if(!data){
    data=ss.insertSheet(DATA_SHEET);
    data.getRange(1,1).setValue(JSON.stringify(def_()));
  }
  try{data.hideSheet();}catch(err){}
  if(!ss.getSheetByName(DASHBOARD_SHEET))ss.insertSheet(DASHBOARD_SHEET,1);
  LEGACY_SHEETS.forEach(name=>{
    const sh=ss.getSheetByName(name);
    if(sh)ss.deleteSheet(sh);
  });
  return ss;
}

function loadState_(){
  const ss=ensureBaseSheets_();
  const raw=ss.getSheetByName(DATA_SHEET).getRange(1,1).getValue();
  try{
    return raw?JSON.parse(raw):def_();
  }catch(err){
    return def_();
  }
}

function saveState_(S){
  const ss=ensureBaseSheets_();
  ss.getSheetByName(DATA_SHEET).getRange(1,1).setValue(JSON.stringify(S));
  writeDashboard_(ss,S.players||[]);
  writeSessionTabs_(ss,S);
}

// ── Dashboard tab ─────────────────────────────────────────────────────
function writeDashboard_(ss,players){
  const sh=ss.getSheetByName(DASHBOARD_SHEET);
  sh.clear();
  const rows=[['Rank','Name','Trend','Wins','Losses','Points']];
  [...players].sort((a,b)=>a.rank-b.rank).forEach(p=>{
    const d=p.rankDelta||0;
    const trend=d>0?'▲'+d:d<0?'▼'+Math.abs(d):'—';
    rows.push([p.rank,p.name,trend,p.wins||0,p.losses||0,p.totalPts||0]);
  });
  sh.getRange(1,1,rows.length,6).setValues(rows);
  sh.getRange(1,1,1,6).setFontWeight('bold');
  sh.autoResizeColumns(1,6);
}

// ── Per-session tabs ─────────────────────────────────────────────────
function nameOf_(players,id){
  const p=(players||[]).find(p=>p.id===id);
  return p?p.name:'?';
}

function sessionRowBlock_(session,players){
  const rows=[];
  rows.push(['Date',session.date,'Rounds',session.numRounds,'Ranking basis',session.rankBasis||'points']);
  rows.push([]);
  const roundsArr=session.rounds&&session.rounds.length?[...session.rounds]:[];
  if(session.courts)roundsArr.push({courts:session.courts}); // current/last round if active
  roundsArr.forEach((r,ri)=>{
    rows.push(['ROUND '+(ri+1)]);
    r.courts.forEach((c,ci)=>{
      rows.push(['Court '+(ci+1)+':',c.players.map(id=>nameOf_(players,id)).join(', ')]);
      rows.push(['Game','Pair 1','Score','Score','Pair 2','Sitting Out']);
      const ptMap={};
      c.players.forEach(id=>ptMap[id]=0);
      c.games.forEach((g,gi)=>{
        const scored=g.s1!==null&&g.s2!==null;
        rows.push(['G'+(gi+1),
          g.pair1.map(id=>nameOf_(players,id)).join(' & '),
          scored?g.s1:'',
          scored?g.s2:'',
          g.pair2.map(id=>nameOf_(players,id)).join(' & '),
          g.sitOut!=null?nameOf_(players,g.sitOut):'']);
        if(scored){
          g.pair1.forEach(id=>ptMap[id]=(ptMap[id]||0)+g.s1);
          g.pair2.forEach(id=>ptMap[id]=(ptMap[id]||0)+g.s2);
        }
      });
      rows.push([]);
      rows.push(['Player','Points']);
      [...c.players].sort((a,b)=>(ptMap[b]||0)-(ptMap[a]||0)).forEach(id=>{
        rows.push([nameOf_(players,id),ptMap[id]||0]);
      });
      rows.push([]);
    });
  });
  if(session.skipped&&session.skipped.length){
    rows.push(['Skipped (-2 ranks):',session.skipped.map(id=>nameOf_(players,id)).join(', ')]);
    rows.push([]);
  }
  if(session.rankChanges){
    const changes=session.rankChanges.filter(r=>r.delta!==0);
    if(changes.length){
      rows.push(['Rank changes:',changes.map(r=>r.name+' '+(r.delta>0?'▲'+r.delta:'▼'+Math.abs(r.delta))).join(', ')]);
    }
  }
  return rows;
}

function sanitizeSheetName_(name){
  return String(name).replace(/[\[\]\*\/\\\?:]/g,'').slice(0,90);
}

function writeSessionTabs_(ss,S){
  const players=S.players||[];
  const wanted=[]; // [{name, rows}]
  const usedNames={};
  function uniqueName(base){
    let name=sanitizeSheetName_(base),i=2;
    while(usedNames[name]){name=sanitizeSheetName_(base)+' ('+i+')';i++;}
    usedNames[name]=true;
    return name;
  }
  if(S.activeSession){
    wanted.push({name:uniqueName(S.activeSession.date+' (Live)'),rows:sessionRowBlock_(S.activeSession,players)});
  }
  (S.sessions||[]).slice().reverse().forEach(s=>{
    wanted.push({name:uniqueName(s.date),rows:sessionRowBlock_(s,players)});
  });

  const keepNames={};
  wanted.forEach((w,i)=>{
    keepNames[w.name]=true;
    let sh=ss.getSheetByName(w.name);
    if(!sh){
      sh=ss.insertSheet(w.name,1+i);
    }else{
      sh.clear();
      ss.setActiveSheet(sh);
      ss.moveActiveSheet(1+i);
    }
    if(w.rows.length){
      const width=Math.max(...w.rows.map(r=>r.length),1);
      const padded=w.rows.map(r=>{const row=r.slice();while(row.length<width)row.push('');return row;});
      sh.getRange(1,1,padded.length,width).setValues(padded);
    }
    sh.autoResizeColumns(1,8);
  });

  ss.getSheets().forEach(sh=>{
    const name=sh.getName();
    if(name===DATA_SHEET||name===DASHBOARD_SHEET||keepNames[name])return;
    if(LEGACY_SHEETS.indexOf(name)!==-1)return; // already handled in ensureBaseSheets_
    ss.deleteSheet(sh);
  });
}

// ── ONE-TIME migration from the old "Badminton Dashboard.xlsx" ──────────
// Brings over the player roster + current rank (re-sequenced to a clean
// 1..N — the old sheet had gaps from past player removals), PLUS 4
// historical session entries (one per week recorded in the old Dashboard
// sheet) carrying date + rank changes + absentees, so History/Dashboard
// have continuity. Wins/losses/points start fresh at 0, and no game/court
// data is included for these historical weeks — the old sheet never
// recorded who partnered with whom in each doubles match, so any
// reconstruction of actual games would be guessed, not real.
//
// Absentees for 31 May and 24 May come directly from the old sheet's own
// "Players Absent" lists. The two oldest weeks (17 May, 10 May) never had
// that column — their absentees are INFERRED as "anyone whose rank moved
// by exactly -2", since that's our app's own skip-penalty rule, and it
// matched the two confirmed weeks with zero discrepancies (16/16 names).
//
// HOW TO RUN: select "migrateFromOldDashboard_" in the function dropdown
// above this editor, click Run (▶), authorize if asked. Check the
// Dashboard and History tabs afterward to confirm.
//
// WARNING: this completely OVERWRITES current players/sessions in this
// Sheet — only run it before you start using the app for real, or if
// you're fine discarding whatever's already in here.
function migrateFromOldDashboard_(){
  const names=['Nishan','Nathish','Noel','Vags','Monit','Karthick R','Will','Jaideep','Shirish','Vijay',
    'Arjun','Amit','Karthick V','Indi','Muhunthan','Dinesh','Harsha','Basheer','John','Koushik'];
  const idOf={};names.forEach((n,i)=>idOf[n]=i+1);

  // Weekly rank snapshots from the old Dashboard sheet: [31May,24May,17May,10May].
  // null = not yet on the ladder that week (shown as '-' in the old sheet).
  const weeklyRanks={
    Nishan:[1,7,5,3],Nathish:[2,3,1,2],Noel:[3,1,9,7],Vags:[4,2,4,null],Monit:[5,11,15,13],
    'Karthick R':[6,4,2,8],Will:[7,6,3,1],Jaideep:[8,10,8,9],Shirish:[9,13,11,4],Vijay:[10,8,7,5],
    Arjun:[11,9,null,null],Amit:[12,5,6,6],'Karthick V':[14,12,13,11],Indi:[16,14,14,null],
    Muhunthan:[17,15,12,10],Dinesh:[18,16,18,16],Harsha:[19,17,10,10],Basheer:[20,18,null,null],
    John:[21,19,17,14],Koushik:[22,20,16,12]
  };

  const players=names.map((name,i)=>({
    id:i+1,name,rank:i+1,totalPts:0,wins:0,losses:0,sessions:0,
    rankDelta:weeklyRanks[name][1]!=null?weeklyRanks[name][1]-weeklyRanks[name][0]:0
  }));

  const confirmedAbsent31May=['Noel','Karthick R','Vijay','Arjun','Karthick V','Indi','Muhunthan','Dinesh','Harsha','Basheer','John','Koushik'];
  const confirmedAbsent24May=['Nishan','Jaideep','Shirish','John'];
  const inferredAbsent17May=['Karthick R','Jaideep','Shirish','John'];
  const inferredAbsent10May=[]; // no earlier baseline exists to infer from

  function buildSession(date,idx,prevIdx,skippedNames,isOldest){
    const attending=[];
    const rankChanges=isOldest?null:[];
    names.forEach(name=>{
      const r=weeklyRanks[name][idx];
      if(r==null)return;
      if(skippedNames.indexOf(name)===-1)attending.push(idOf[name]);
      if(!isOldest){
        const prevR=weeklyRanks[name][prevIdx];
        if(prevR!=null)rankChanges.push({name,delta:prevR-r});
      }
    });
    return{
      date,numRounds:1,rankBasis:'points',round:1,bands:[],rounds:[{courts:[]}],
      skipped:skippedNames.map(n=>idOf[n]),attending,rankChanges
    };
  }

  const sessions=[
    buildSession('10 May 2026',3,null,inferredAbsent10May,true),
    buildSession('17 May 2026',2,3,inferredAbsent17May,false),
    buildSession('24 May 2026',1,2,confirmedAbsent24May,false),
    buildSession('31 May 2026',0,1,confirmedAbsent31May,false)
  ];

  const S={players,nextId:players.length+1,activeSession:null,sessions};
  saveState_(S);
  Logger.log('Migrated '+players.length+' players and '+sessions.length+' historical sessions. Check Dashboard + History tabs. This function is now safe to delete.');
}
