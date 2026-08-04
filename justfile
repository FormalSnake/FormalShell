default: build
build:
    git add -A && nix build .#formalshell
smoke:
    ./dev/smoke-niri.sh
lint:
    git add -A && nix flake check -L
# QML_XHR_ALLOW_FILE_READ: tst_menu_emoji.qml XHR-loads shell/Menu/emoji.json,
# which sits outside the test file's own directory subtree.
# -import tests/stubs: resolves the `qs.Core` module for the tests that
# instantiate real shell components (tst_cell_geometry.qml).
test:
    nix develop -c env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 qmltestrunner -import tests/stubs -input tests

vm-up:
    ./dev/vm.sh start
vm-down:
    ./dev/vm.sh stop
vm-build:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'git add -A && nix build --print-out-paths .#formalshell'
vm-test:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'nix develop -c env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 qmltestrunner -import tests/stubs -input tests'
vm-lint:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'git add -A && nix flake check -L'
vm-smoke *FLAGS:
    ./dev/vm.sh smoke {{FLAGS}}
# nix/testvm.nix's services.greetd needs a rebuilt VM (`vm-down && vm-up`)
# before this passes for the first time — separate from vm-smoke since
# greetd's default_session is a standing system service, not a fresh nested
# compositor this recipe spins up itself (see dev/smoke-greeter.sh's own
# header comment). Pulls artifacts/greeter/ back with a plain scp, mirroring
# dev/vm.sh's own ssh/key wiring rather than adding a second command to that
# script for one caller.
vm-greeter:
    ./dev/vm.sh sync
    ./dev/vm.sh run './dev/smoke-greeter.sh'
    mkdir -p artifacts/greeter
    scp -P 2222 -i dev/.testvm/keys/test_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -r test@localhost:formalshell/artifacts/greeter/. artifacts/greeter/
