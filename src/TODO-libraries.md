Library Analysis

1. BaoFactoryDeployLib (62 lines)
   Purpose: Pure CREATE2 deployment logic via Nick's Factory

Functions:

deploy() → Deploy BaoFactory bootstrap via Nick's Factory
Characteristics:

No forge-std dependency (no vm cheats)
Works in production and testing environments
Pure deployment mechanics only
Used by:

BaoFactoryFoundryLib (calls BaoFactoryDeployLib.deploy())
Referenced in BaoFactoryBytecode.sol comments 2. BaoFactoryDeployment (180 lines)
Purpose: Complete deployment orchestration + readiness checks

Functions:

Prediction: predictBaoFactoryAddress()
Queries: isBaoFactoryDeployed(), isBaoFactoryFunctional(), isOperator()
Requirements: requireBaoFactory(), requireFunctionalBaoFactory(), requireOperator()
Actions: deployBaoFactory(), upgradeBaoFactory(), upgradeBaoFactoryToV1(), setBaoFactoryOperator()
Characteristics:

No forge-std dependency
Complete API for deployment lifecycle
Used by production scripts AND tests
Contains its own deployment logic (duplicates BaoFactoryDeployLib's deploy())
Used by:

Deployment.sol
DeploymentTesting.sol
bao-base/test/deployment/\*.sol
BaoFactoryDeployment.t.sol 3. BaoFactoryFoundryLib (53 lines)
Purpose: Foundry-specific test utilities requiring vm cheats

Functions:

ensureNicksFactory() → vm.etch Nick's Factory if missing
deployForTesting() → Etch + deploy (wraps BaoFactoryDeployLib.deploy())
setOperatorForTesting() → vm.prank(owner) + set operator
deployWithOperator() → Deploy + set caller as operator
Characteristics:

Requires forge-std/Vm.sol - cannot be used in production
Convenience wrappers with vm.prank built-in
Designed for test setup where you need to act as owner
Used by:

Referenced in README for downstream test usage
Currently no actual imports found in source files (may be unused or planned)
Overlap Analysis
Feature BaoFactoryDeployLib BaoFactoryDeployment BaoFactoryFoundryLib
Deploy bootstrap ✅ deploy() ✅ deployBaoFactory() ✅ deployForTesting()
Upgrade to v1 ❌ ✅ upgradeBaoFactoryToV1() ❌
Set operator ❌ ✅ setBaoFactoryOperator() ✅ setOperatorForTesting()
Query status ❌ ✅ is*(), require*() ❌
Requires vm ❌ ❌ ✅
Etches Nick's ❌ ❌ ✅
Observations
BaoFactoryDeployment.deployBaoFactory() duplicates BaoFactoryDeployLib.deploy() - The deployment assembly code is nearly identical. This is redundant.

BaoFactoryFoundryLib appears unused - No actual imports in source code (only references in README/comments). It wraps BaoFactoryDeployLib, but the tests use BaoFactoryDeployment instead.

The libraries serve different audiences:

BaoFactoryDeployLib: Low-level, production-safe deployment
BaoFactoryDeployment: Complete API for scripts and tests
BaoFactoryFoundryLib: Test convenience with vm cheats
Recommendation
Option A: Keep all three, but deduplicate

Have BaoFactoryDeployment.deployBaoFactory() delegate to BaoFactoryDeployLib.deploy()
Keep BaoFactoryFoundryLib for downstream test convenience
Option B: Consolidate to two

Merge BaoFactoryDeployLib into BaoFactoryDeployment (it's only used by FoundryLib)
Keep BaoFactoryFoundryLib separate due to vm dependency
Option C: Consolidate to one + test helper

BaoFactoryDeployment becomes the single production library
BaoFactoryFoundryLib becomes a thin test wrapper (or remove if unused)
Delete BaoFactoryDeployLib
What direction would you like to take?
