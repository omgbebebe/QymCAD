{
  description = "QymCAD - parametric 2D/3D CAD (egui + wgpu)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = lib.genAttrs systems;

      version = (lib.fromTOML (lib.readFile ./Cargo.toml)).workspace.package.version;

      # What the window stack loads at runtime (winit/x11rb and wayland-client dlopen these;
      # wgpu loads the Vulkan/GL drivers). Headers are not needed - everything links at runtime.
      runtimeLibs = pkgs: with pkgs; [
        libGL
        libxcb
        libX11
        libXcursor
        libXi
        libXrandr
        libxkbcommon
        opencascade-occt
        vulkan-loader
        wayland
      ];

      qymcadFor = pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "qymcad";
          inherit version;
          src = lib.cleanSource ./.;

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [ makeWrapper pkg-config ];
          buildInputs = runtimeLibs pkgs;

          # where the kernel's build.rs looks for the system OpenCASCADE
          env = {
            OCCT_INCLUDE_DIR = "${pkgs.opencascade-occt}/include/opencascade";
            OCCT_LIB_DIR = "${pkgs.opencascade-occt}/lib";
          };

          # the root manifest is a virtual workspace: build only the app crate,
          # install by hand (cargo install does not accept a virtual manifest)
          cargoBuildFlags = [ "--package" "qymcad" ];
          doCheck = false;
          installPhase = ''
            install -Dm755 target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/qymcad -t $out/bin
            wrapProgram $out/bin/qymcad \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath (runtimeLibs pkgs)}
          '';

          meta = {
            description = "QymCAD - parametric 2D/3D CAD (egui + wgpu)";
            homepage = "https://cad.qymis.tech";
            license = lib.licenses.agpl3Plus;
            mainProgram = "qymcad";
          };
        };
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = qymcadFor pkgs;
          qymcad = qymcadFor pkgs;
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              clippy
              rustc
              rustfmt
              rust-analyzer
              pkg-config
              just
              python3
            ] ++ runtimeLibs pkgs;

            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
          };
        });
    };
}
