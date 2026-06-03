const express = require('express');
const { spawn } = require('child_process');
const path    = require('path');
const os      = require('os');

const app  = express();
const PORT = process.env.PORT || 3000;

const ACTIONS = {
  'clear-teams-cache':   'setup/Clear-TeamsCache.ps1',
  'gpupdate':            'setup/GPUpdate.ps1',
  'outlook-teams-addin': 'setup/Outlook-TeamsMeetingAddin.ps1',
  'restart-pc':          'setup/Restart-PC.ps1',
  'check-uptime':        'setup/Get-Uptime.ps1',
  'sfc-scannow':         'setup/SFC-Scan.ps1',
  'chkdsk':              'setup/ChkDsk.ps1',
};

app.use(express.static(__dirname));

// Returns system uptime so the browser can display it live
app.get('/api/uptime', (req, res) => {
  const secs  = os.uptime();
  const days  = Math.floor(secs / 86400);
  const hours = Math.floor((secs % 86400) / 3600);
  const mins  = Math.floor((secs % 3600) / 60);
  res.json({ seconds: secs, days, hours, mins, warn: secs >= 86400 });
});

app.post('/api/run/:action', (req, res) => {
  const scriptRel = ACTIONS[req.params.action];
  if (!scriptRel) return res.status(404).json({ error: 'Unknown action' });

  const scriptPath = path.join(__dirname, scriptRel);

  const ps = spawn('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
  ]);

  // Stream PowerShell output back to the browser
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Transfer-Encoding', 'chunked');

  ps.stdout.on('data', d => res.write(d));
  ps.stderr.on('data', d => res.write(d));
  ps.on('close', code => res.end(`\n[Done — exit code ${code}]`));
  ps.on('error', err => res.status(500).end(`[Error: ${err.message}]`));
});

app.listen(PORT, () => {
  console.log(`\n  Barclays IT Self-Service Portal`);
  console.log(`  http://localhost:${PORT}\n`);
});
