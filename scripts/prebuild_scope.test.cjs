const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const { SUPPORTED_RELEASE } = require('./wgpu_native_release.cjs');

for (const type of ['module', 'commonjs']) {
  test(`prebuild and release helper work inside a ${type} consumer scope`, () => {
    const temporary = fs.realpathSync(os.tmpdir());
    const prefix = 'wgpu-prebuild-scope-';
    const root = fs.realpathSync(fs.mkdtempSync(path.join(temporary, prefix)));
    try {
      fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ type }));
      // Node inherits this scope through .mooncakes, unlike node_modules.
      const binding = path.join(root, '.mooncakes', 'Milky2018', 'wgpu_mbt');
      fs.mkdirSync(path.join(binding, 'scripts'), { recursive: true });
      for (const file of ['build.cjs', 'scripts/wgpu_native_release.cjs']) {
        fs.copyFileSync(path.join(__dirname, '..', file), path.join(binding, file));
      }
      const execute = (file, args = []) => {
        const result = spawnSync(process.execPath, [path.join(binding, file), ...args], {
          cwd: root,
          env: { ...process.env, MBT_WGPU_LINK_MODE: 'dynamic', MBT_WGPU_NATIVE_SANITIZE: '' },
          encoding: 'utf8',
          timeout: 10000,
        });
        assert.equal(result.error, undefined);
        assert.equal(result.signal, null);
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trim();
      };
      const prebuild = JSON.parse(execute('build.cjs'));
      assert.equal(typeof prebuild.vars.WGPU_MBT_C_STUB_CC_FLAGS, 'string');
      assert.deepEqual(prebuild.link_configs, []);
      assert.equal(
        execute('scripts/wgpu_native_release.cjs', ['meta', '--field', 'tag']),
        SUPPORTED_RELEASE.tag,
      );
      assert.equal(fs.existsSync(path.join(root, '.mooncakes', 'package.json')), false);
    } finally {
      assert.equal(path.dirname(root), temporary);
      assert.equal(path.basename(root).startsWith(prefix), true);
      assert.equal(fs.lstatSync(root).isSymbolicLink(), false);
      fs.rmSync(root, { recursive: true });
    }
  });
}
