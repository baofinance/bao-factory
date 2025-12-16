# bao-factory

Canonical Bao Factory contracts plus deterministic deployment helpers. We keep the factory in this dedicated subtree because its build needs to be _boringly consistent_: the same compiler flags, the same bytecode blob, and therefore the same deterministic deployment addresses across every downstream repo. The tree is vendored into `bao-base`, so consumers get updates via git rather than npm crates or copy/paste.

## Production Deployment Guide

The `script/bao-factory` CLI handles all deployment operations. Run `--help` for full options.

### Initial Factory Deployment

This installs a non-functional, but upgradeable, factory. It does it by:

- deploying via Nick's factory a contract that can be UUPS upgraded only by the Bao Harbor multisig. The owner() function returns that address.
- the constructor in this "bootstrapper" contract deploys a minimal UUPS proxy whose initial implementation is itself. This is the actual factory whose address is deterministic based on the salt provided to Nick's factory.

```bash
# Deploy the bootstrap factory via Nick's Factory (deterministic address)
bao-factory --deploy --network mainnet --account deployer
```

So now we have a factory deployed at a predictable address but it has no factory functionality. Factory functionality comes with the next step.

We verify in etherscan the factory code.

```bash
bao-factory --verify --network mainnet
```

On etherscan we also manually verify it as a proxy.

### Upgrading to BaoFactory_v1

The bootstrap factory must be upgraded to `BaoFactory_v1` before use:

```bash
# 1. Deploy the implementation and get upgrade instructions
bao-factory --implementation src/BaoFactory_v1.sol:BaoFactory_v1 \
  --network mainnet --account deployer

# 2. The script outputs cast commands for the owner multisig to execute:
#    - upgradeToAndCall(address,bytes) to point proxy at new implementation
#    - setOperator(address,uint256) to authorize deployers
```

The functional factory implementation is now deployed and verified on etherscan. The proxy needs to be upgraded to point to this new implementation. This is done by the upgradeToAndCall call sent to it which can only be done via the Bao Harbor multisig.

In order to use the BaoFactory_v1 you need to be an operator. So make the setOperator call on the BaoHarbor multisig

For Safe multisig, use Transaction Builder with the calldata from:

```bash
cast calldata 'upgradeToAndCall(address,bytes)' <NEW_IMPL_ADDRESS> 0x
cast calldata 'setOperator(address,uint256)' <OPERATOR_ADDRESS> 86400
```

## Source Layout

- `src/BaoFactory.sol` – upgradeable factory implementation with the production owner baked in.
- `src/BaoFactoryBytecode.sol` – captured creation code, Nick's Factory constants, and the predicted deterministic addresses.
- `src/BaoFactoryDeployment.sol` – shared helper that downstream repos import to "ensure" a BaoFactory exists (production bytecode or current build).
- `src/BaoFactoryDeployLib.sol` / `src/BaoFactoryFoundryLib.sol` – lower-level deploy helpers plus Forge-specific utilities (e.g., `vm.etch`).
- `test/` – unit tests that cover the deterministic deployment, operator management, and upgrade flows.

## Deploying from Other Repos

Import the helper and call the mode that matches your use case. Every downstream repo (bao-base included) now depends on this library instead of carrying bespoke deployment shims, so treat it as the single source of truth:

```solidity
import { BaoFactoryDeployment } from "@bao-factory/BaoFactoryDeployment.sol";

contract MyScript {
  function _ensureBaoFactory() internal returns (address baoFactory) {
    // Production (captured bytecode + owner verification)
    baoFactory = BaoFactoryDeployment.ensureBaoFactoryProduction();
  }
}
```

For tests that must track local edits to `BaoFactory.sol`, call `ensureBaoFactoryCurrentBuild()` instead. Both functions verify the proxy runtime code hash and enforce that the owner matches the embedded production multisig, so downstream code does not need to duplicate those checks. `DeploymentJsonScript`, `DeploymentTesting`, and the other bao-base mixins simply forward to these helpers now that `script/deployment/DeploymentInfrastructure.sol` has been deleted.

Practical guidance for consumers:

- **Scripts** – Call `ensureBaoFactoryProduction()` when you must guarantee the production bytecode/owner pairing before running a deployment session. The helper will deterministically deploy via Nick's Factory if the proxy is missing, then assert the invariants.
- **Tests** – Use `ensureBaoFactoryCurrentBuild()` inside Foundry harnesses when you intentionally need to exercise local edits. This matches the pattern in `DeploymentTesting` and keeps traceability between code changes and deterministic test deployments.
- **Address prediction only** – Reach for `predictBaoFactoryAddress()` / `predictBaoFactoryImplementation()` (or their salt/hash overloads) when you only need the deterministic addresses without forcing a deploy.

The deployed proxy uses UUPS upgradeability. Shipping a new BaoFactory variant usually just means rolling out a new implementation and having the production owner upgrade the existing proxy to the fresh logic. Downstream repos should assume the address stays constant while the logic can evolve via upgrades.

Use `predictBaoFactoryAddress()` / `predictBaoFactoryImplementation()` if you only need the deterministic addresses without deploying anything. Pass a custom salt + creation-code hash to the overloaded versions when experimenting with alternative variants.

## Keeping the Bytecode Current

Treat `src/BaoFactory.sol` as nearly frozen. Only touch it when you intentionally want to mint a _new_ BaoFactory release, because any change forces every deployment pipeline to update bytecode snapshots.

1. Make the intentional change in `src/BaoFactory.sol` (and document _why_ in the commit message—future maintainers need that context).
2. Run the extractor to regenerate the captured creation code and metadata. This produces the implementation bytecode that existing proxies will upgrade into, so keep the toolchain pinned and deterministic:

   ```bash
   cd lib/bao-factory
   ./script/bao-factory --extract
   ```

   This overwrites `src/BaoFactoryBytecode.sol` with the new creation code, hashes, and predicted addresses.

3. Commit both the Solidity change and the regenerated bytecode so downstream repos stay deterministic.

## Testing

Inside `lib/bao-factory` run:

```bash
yarn test           # convenience wrapper that invokes forge test
```

Downstream projects should rely on these tests rather than duplicating BaoFactory harnesses. When integration tests need a deployed factory on a fresh chain, use `BaoFactoryFoundryLib.deployForTesting()` (which will `vm.etch` Nick's Factory if required) and then configure operators through the helper. bao-base now imports the FundedVault/NonPayableVault mocks directly from `lib/bao-factory/test/` to keep CREATE3-with-value coverage centralized; prefer doing the same if you need those funded scenarios elsewhere.
