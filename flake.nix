{
  description = "vortex — reproducible dev environment (Bun runtime + Kubernetes toolchain)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Build the devShell for every common dev platform; flake.lock pins the
      # exact nixpkgs revision, so every machine gets byte-identical tool versions.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "vortex-dev";

          packages = with pkgs; [
            # --- app runtime (ADR-001) ---
            bun

            # --- contracts ---
            buf # protobuf lint + breaking-change checks

            # --- Kubernetes (Phase 2) ---
            kubectl
            kubernetes-helm # the k8s "helm" — NOT the `helm` attribute
            kind
            cloud-provider-kind # LoadBalancer support for kind (Gateway API, ADR-013)
            k9s # cluster TUI (DX)

            # --- Cloud / IaC (ADR-010) ---
            opentofu # `tofu` — OpenTofu, NOT terraform (MPL vs BSL)
            awscli2 # `aws` — configure creds + sanity-check (aws sts get-caller-identity)

            # --- GitOps (Phase 4) ---
            kubeseal # seal plaintext Secrets into commit-safe SealedSecret CRDs
            argocd # ArgoCD CLI — login/app/sync from the terminal

            # --- CI / GitHub ---
            gh # GitHub CLI — open/merge PRs, watch Actions runs

            # --- misc ---
            go # builds cloud-provider-kind deps / future polyglot services
          ];

          # Note: Docker itself is provided by the host (NixOS `virtualisation.docker`),
          # not this shell — kind/compose talk to the system Docker daemon.
          shellHook = ''
            echo ""
            echo "🌀 vortex devshell"
            echo "   bun $(bun --version)  ·  kubectl $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')  ·  kind $(kind version 2>/dev/null | awk '{print $2}')  ·  helm $(helm version --short 2>/dev/null)  ·  tofu $(tofu version 2>/dev/null | head -1 | awk '{print $2}')"
            echo "   tip: cloud-provider-kind needs the system docker socket — run it as: sudo \$(which cloud-provider-kind)"
            echo ""
          '';
        };
      });
    };
}
