# Patch CI in BOTH trees (src keeps in sync with the mirror going forward).
import io, shutil, sys
sys.stdout.reconfigure(encoding='utf-8')
src_root = r'C:\Users\user\Documents\shuro-source-2.6.2\src'
mirror_root = r'C:\Users\user\Desktop\shuro\shuro'
old1 = 'liblzma-dev libstdc++-12-dev libsecret-1-dev libmpv-dev mpv\n'
new1 = ('liblzma-dev libstdc++-12-dev libsecret-1-dev libmpv-dev mpv \\\n'
        '            libkeybinder-3.0-dev\n')
for name in ['ci.yml', 'release.yml']:
    src_p = src_root + r'\.github\workflows\\' + name
    mir_p = mirror_root + r'\.github\workflows\\' + name
    src_txt = io.open(src_p, encoding='utf-8').read()
    assert src_txt.count(old1) == 1, (name, 'toolchain anchor')
    src_txt = src_txt.replace(old1, new1)
    io.open(src_p, 'w', encoding='utf-8', newline='').write(src_txt)
    shutil.copyfile(src_p, mir_p)
    print('patched+synced', name)

# release.yml deb runtime dependency (mirror only holds the built repo state;
# keep src in sync too for future mirrors)
for name in ['release.yml']:
    for root in [src_root, mirror_root]:
        rel_p = root + r'\.github\workflows\\' + name
        rel = io.open(rel_p, encoding='utf-8').read()
        old2 = 'Depends: libgtk-3-0 | libgtk-3-0t64, libayatana-appindicator3-1, libsecret-1-0, libmpv2'
        new2 = 'Depends: libgtk-3-0 | libgtk-3-0t64, libayatana-appindicator3-1, libsecret-1-0, libmpv2, libkeybinder-3.0-0'
        if rel.count(old2) == 1:
            rel = rel.replace(old2, new2)
            io.open(rel_p, 'w', encoding='utf-8', newline='').write(rel)
            print('deb Depends patched:', root)
        else:
            # already patched in the mirror
            assert new2 in rel, (root, 'deb depends missing')
            print('deb Depends already patched:', root)
