// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {BaoFactory} from "@bao-factory/BaoFactory.sol";
import {BaoFactory_v1} from "@bao-factory/BaoFactory_v1.sol";
import {BaoFactoryDeployment} from "@bao-factory/BaoFactoryDeployment.sol";
import {BaoFactoryBytecode} from "@bao-factory/BaoFactoryBytecode.sol";
import {IBaoFactory} from "@bao-factory/IBaoFactory.sol";

/// @dev Simple contract used for deployment tests
contract SimpleDeployable {
    uint256 public value;

    constructor(uint256 _value) {
        value = _value;
    }
}

/// @dev Wrapper contract to test library reverts via external calls
contract DeploymentLibraryCaller {
    function callRequireBaoFactory() external view {
        BaoFactoryDeployment.requireBaoFactory();
    }

    function callRequireFunctionalBaoFactory() external view {
        BaoFactoryDeployment.requireFunctionalBaoFactory();
    }

    function callRequireOperator(address op) external view {
        BaoFactoryDeployment.requireOperator(op);
    }

    function callUpgradeBaoFactoryToV1() external {
        BaoFactoryDeployment.upgradeBaoFactoryToV1();
    }
}

/// @title BaoFactoryDeploymentTest
/// @notice Tests for BaoFactoryDeployment library
/// @dev Tests query functions (is*/require*) and action functions (deploy/upgrade/setOperator)
contract BaoFactoryDeploymentTest is Test {
    address internal owner = BaoFactoryBytecode.OWNER;
    address internal operator = makeAddr("deployment-operator");
    DeploymentLibraryCaller internal caller;

    /// @dev ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public {
        caller = new DeploymentLibraryCaller();
    }

    /// @dev Read the implementation address from proxy's ERC1967 slot
    function _getImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    /// @dev Helper to upgrade as owner (handles multi-call prank)
    function _upgradeToV1AsOwner() internal {
        vm.startPrank(owner);
        BaoFactoryDeployment.upgradeBaoFactoryToV1();
        vm.stopPrank();
    }

    /// @dev Helper to set operator as owner
    function _setOperatorAsOwner(address op, uint256 duration) internal {
        address proxy = BaoFactoryDeployment.predictBaoFactoryAddress();
        vm.startPrank(owner);
        IBaoFactory(proxy).setOperator(op, duration);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                           PREDICTION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_PredictBaoFactoryAddress_MatchesBytecode_() public pure {
        address predicted = BaoFactoryDeployment.predictBaoFactoryAddress();
        assertEq(predicted, BaoFactoryBytecode.PREDICTED_PROXY, "prediction should match bytecode constant");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        QUERY TESTS - BEFORE DEPLOYMENT
    //////////////////////////////////////////////////////////////////////////*/

    function test_IsBaoFactoryDeployed_FalseBeforeDeployment_() public view {
        assertFalse(BaoFactoryDeployment.isBaoFactoryDeployed(), "should be false before deployment");
    }

    function test_IsBaoFactoryFunctional_FalseBeforeDeployment_() public view {
        assertFalse(BaoFactoryDeployment.isBaoFactoryFunctional(), "should be false before deployment");
    }

    function test_IsOperator_FalseBeforeDeployment_() public view {
        assertFalse(BaoFactoryDeployment.isOperator(operator), "should be false before deployment");
    }

    function test_RequireBaoFactory_RevertsBeforeDeployment_() public {
        vm.expectRevert(BaoFactoryDeployment.BaoFactoryNotDeployed.selector);
        caller.callRequireBaoFactory();
    }

    function test_RequireFunctionalBaoFactory_RevertsBeforeDeployment_() public {
        vm.expectRevert(BaoFactoryDeployment.BaoFactoryNotFunctional.selector);
        caller.callRequireFunctionalBaoFactory();
    }

    function test_RequireOperator_RevertsBeforeDeployment_() public {
        vm.expectRevert(abi.encodeWithSelector(BaoFactoryDeployment.BaoFactoryOperatorNotSet.selector, operator));
        caller.callRequireOperator(operator);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ACTION TESTS - DEPLOY
    //////////////////////////////////////////////////////////////////////////*/

    function test_DeployBaoFactory_DeploysProxy_() public {
        address proxy = BaoFactoryDeployment.deployBaoFactory();
        assertTrue(proxy != address(0), "proxy should be non-zero");
        assertTrue(proxy.code.length > 0, "proxy should have code");
        assertEq(proxy, BaoFactoryBytecode.PREDICTED_PROXY, "proxy should match prediction");
    }

    function test_DeployBaoFactory_Idempotent_() public {
        address proxy1 = BaoFactoryDeployment.deployBaoFactory();
        address proxy2 = BaoFactoryDeployment.deployBaoFactory();
        assertEq(proxy1, proxy2, "repeated calls should return same proxy");
    }

    function test_DeployBaoFactory_OwnerIsCorrect_() public {
        address proxy = BaoFactoryDeployment.deployBaoFactory();
        assertEq(BaoFactory(proxy).owner(), owner, "owner should match");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        QUERY TESTS - AFTER DEPLOY, BEFORE UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    function test_IsBaoFactoryDeployed_TrueAfterDeploy_() public {
        BaoFactoryDeployment.deployBaoFactory();
        assertTrue(BaoFactoryDeployment.isBaoFactoryDeployed(), "should be true after deployment");
    }

    function test_IsBaoFactoryFunctional_FalseAfterDeployBeforeUpgrade_() public {
        BaoFactoryDeployment.deployBaoFactory();
        assertFalse(BaoFactoryDeployment.isBaoFactoryFunctional(), "should be false before upgrade");
    }

    function test_RequireBaoFactory_SucceedsAfterDeploy_() public {
        BaoFactoryDeployment.deployBaoFactory();
        BaoFactoryDeployment.requireBaoFactory(); // Should not revert
    }

    function test_RequireFunctionalBaoFactory_RevertsAfterDeployBeforeUpgrade_() public {
        BaoFactoryDeployment.deployBaoFactory();
        vm.expectRevert(BaoFactoryDeployment.BaoFactoryNotFunctional.selector);
        caller.callRequireFunctionalBaoFactory();
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ACTION TESTS - UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    function test_UpgradeBaoFactoryToV1_MakesFunctional_() public {
        address proxy = BaoFactoryDeployment.deployBaoFactory();

        // Before upgrade: bootstrap implementation
        address implBefore = _getImplementation(proxy);
        assertTrue(implBefore != address(0), "should have bootstrap impl");

        _upgradeToV1AsOwner();

        // After upgrade: v1 implementation (different address)
        address implAfter = _getImplementation(proxy);
        assertTrue(implAfter != address(0), "should have v1 impl");
        assertTrue(implAfter != implBefore, "implementation should change");
        assertTrue(BaoFactoryDeployment.isBaoFactoryFunctional(), "should be functional after upgrade");
    }

    function test_UpgradeBaoFactory_WithExplicitImpl_() public {
        address proxy = BaoFactoryDeployment.deployBaoFactory();

        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        vm.prank(owner);
        BaoFactoryDeployment.upgradeBaoFactory(address(v1Impl));

        // Verify implementation is exactly what we deployed
        address implAfter = _getImplementation(proxy);
        assertEq(implAfter, address(v1Impl), "implementation should be v1Impl");
        assertTrue(BaoFactoryDeployment.isBaoFactoryFunctional(), "should be functional after upgrade");
    }

    function test_UpgradeBaoFactory_UnauthorizedReverts_() public {
        BaoFactoryDeployment.deployBaoFactory();

        address outsider = makeAddr("outsider");
        vm.prank(outsider);
        vm.expectRevert();
        caller.callUpgradeBaoFactoryToV1();
    }

    function test_UpgradeBaoFactory_ImplementationChangesOnEachUpgrade_() public {
        address proxy = BaoFactoryDeployment.deployBaoFactory();
        address implBootstrap = _getImplementation(proxy);

        // First upgrade
        BaoFactory_v1 v1Impl1 = new BaoFactory_v1();
        vm.prank(owner);
        BaoFactoryDeployment.upgradeBaoFactory(address(v1Impl1));
        address implV1First = _getImplementation(proxy);
        assertEq(implV1First, address(v1Impl1), "should be first v1 impl");
        assertTrue(implV1First != implBootstrap, "should differ from bootstrap");

        // Second upgrade (new v1 instance)
        BaoFactory_v1 v1Impl2 = new BaoFactory_v1();
        vm.prank(owner);
        BaoFactoryDeployment.upgradeBaoFactory(address(v1Impl2));
        address implV1Second = _getImplementation(proxy);
        assertEq(implV1Second, address(v1Impl2), "should be second v1 impl");
        assertTrue(implV1Second != implV1First, "should differ from first v1");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        QUERY TESTS - AFTER UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    function test_IsBaoFactoryFunctional_TrueAfterUpgrade_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();
        assertTrue(BaoFactoryDeployment.isBaoFactoryFunctional(), "should be functional");
    }

    function test_RequireFunctionalBaoFactory_SucceedsAfterUpgrade_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();
        BaoFactoryDeployment.requireFunctionalBaoFactory(); // Should not revert
    }

    function test_IsOperator_FalseBeforeSet_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();
        assertFalse(BaoFactoryDeployment.isOperator(operator), "operator should not be set initially");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ACTION TESTS - SET OPERATOR
    //////////////////////////////////////////////////////////////////////////*/

    function test_SetBaoFactoryOperator_SetsOperator_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();
        _setOperatorAsOwner(operator, 1 days);
        assertTrue(BaoFactoryDeployment.isOperator(operator), "operator should be set");
    }

    function test_SetBaoFactoryOperator_UnauthorizedReverts_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();

        address proxy = BaoFactoryDeployment.predictBaoFactoryAddress();
        address outsider = makeAddr("outsider");
        vm.prank(outsider);
        vm.expectRevert();
        IBaoFactory(proxy).setOperator(operator, 1 days);
    }

    function test_RequireOperator_SucceedsAfterSet_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();
        _setOperatorAsOwner(operator, 1 days);
        BaoFactoryDeployment.requireOperator(operator); // Should not revert
    }

    function test_RequireOperator_RevertsIfNotSet_() public {
        BaoFactoryDeployment.deployBaoFactory();
        _upgradeToV1AsOwner();

        vm.expectRevert(abi.encodeWithSelector(BaoFactoryDeployment.BaoFactoryOperatorNotSet.selector, operator));
        caller.callRequireOperator(operator);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        INTEGRATION: FULL WORKFLOW
    //////////////////////////////////////////////////////////////////////////*/

    function test_FullWorkflow_DeployUpgradeOperatorDeploy_() public {
        // 1. Deploy bootstrap (permissionless)
        address proxy = BaoFactoryDeployment.deployBaoFactory();
        assertTrue(BaoFactoryDeployment.isBaoFactoryDeployed(), "deployed");
        assertFalse(BaoFactoryDeployment.isBaoFactoryFunctional(), "not yet functional");

        // 2. Upgrade to v1 (owner only)
        _upgradeToV1AsOwner();
        assertTrue(BaoFactoryDeployment.isBaoFactoryFunctional(), "functional");

        // 3. Set operator (owner only)
        _setOperatorAsOwner(operator, 7 days);
        assertTrue(BaoFactoryDeployment.isOperator(operator), "operator set");

        // 4. Operator can deploy (operator authorized)
        IBaoFactory factory = IBaoFactory(proxy);
        bytes memory initCode = abi.encodePacked(type(SimpleDeployable).creationCode, abi.encode(uint256(42)));
        bytes32 salt = keccak256("workflow.test");

        vm.prank(operator);
        address deployed = factory.deploy(initCode, salt);
        assertEq(SimpleDeployable(deployed).value(), 42, "deployed contract works");
    }
}
