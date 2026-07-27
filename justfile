default: build
build:
    git add -A && nix build .#formalshell
smoke:
    ./dev/smoke-niri.sh
lint:
    git add -A && nix flake check -L
test:
    nix develop -c env QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
