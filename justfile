default: build
build:
    git add -A && nix build .#formalshell
smoke:
    ./dev/smoke-niri.sh
lint:
    git add -A && nix flake check -L
test:
    nix develop -c env QT_QPA_PLATFORM=offscreen qmltestrunner -input tests

vm-up:
    ./dev/vm.sh start
vm-down:
    ./dev/vm.sh stop
vm-build:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'git add -A && nix build --print-out-paths .#formalshell'
vm-test:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'nix develop -c env QT_QPA_PLATFORM=offscreen qmltestrunner -input tests'
vm-lint:
    ./dev/vm.sh sync
    ./dev/vm.sh run 'git add -A && nix flake check -L'
vm-smoke *FLAGS:
    ./dev/vm.sh smoke {{FLAGS}}
