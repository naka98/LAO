const { execSync } = require('child_process');

const userAgent = process.env.npm_config_user_agent || '';
const isYarn = userAgent.includes('yarn');
const buildOnly = process.argv.includes('--build-only');

const pm = isYarn ? 'yarn' : 'npm';
console.log(`[LAO] Action: ${buildOnly ? 'Build Only' : 'Install & Build'} using ${pm}`);

function run(cmd) {
  console.log(`[LAO] Executing: ${cmd}`);
  execSync(cmd, { stdio: 'inherit' });
}

try {
  if (isYarn) {
    if (!buildOnly) {
      run('yarn --cwd cli install');
      run('yarn --cwd web install');
    }
    run('yarn --cwd cli run build');
    run('yarn --cwd web run build');
  } else {
    if (!buildOnly) {
      try {
        run('npm ci --prefix cli');
      } catch (e) {
        run('npm install --prefix cli');
      }
      try {
        run('npm ci --prefix web');
      } catch (e) {
        run('npm install --prefix web');
      }
    }
    run('npm run build --prefix cli');
    run('npm run build --prefix web');
  }
  console.log('[LAO] Complete!');
} catch (err) {
  console.error('[LAO] Execution failed:', err.message);
  process.exit(1);
}
