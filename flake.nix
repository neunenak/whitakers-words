{
  description = "Whitaker's WORDS - Latin-English dictionary with inflectional morphology";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gnat
            gprbuild
          ];

          shellHook = ''
            echo "Whitaker's WORDS development environment"
            echo "Ada toolchain: $(gnat --version | head -1)"
            echo ""
            echo "Build commands:"
            echo "  make          - Full build (code + data)"
            echo "  make commands - Build executables only"
            echo "  make test     - Run tests"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "whitakers-words";
          version = "0.0.0-dev";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            gnat
            gprbuild
          ];

          buildPhase = ''
            make
          '';

          installPhase = ''
            mkdir -p $out/bin $out/share/whitakers-words

            # Install executables
            cp bin/words $out/bin/

            # Install data files
            cp *.GEN *.SEC $out/share/whitakers-words/

            # Wrap the binary to find data files
            mv $out/bin/words $out/bin/.words-unwrapped
            cat > $out/bin/words << EOF
            #!/bin/sh
            export WHITAKERS_WORDS_DATADIR="\''${WHITAKERS_WORDS_DATADIR:-$out/share/whitakers-words}"
            exec $out/bin/.words-unwrapped "\$@"
            EOF
            chmod +x $out/bin/words
          '';

          meta = with pkgs.lib; {
            description = "Latin-English dictionary with inflectional morphology support";
            homepage = "http://mk270.github.io/whitakers-words/";
            license = licenses.free;
            platforms = platforms.unix;
            mainProgram = "words";
          };
        };
      });
}
