// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {Test, Vm} from "forge-std/Test.sol";
import {LibClone} from "@solady/utils/LibClone.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";

import {BaoFactory} from "@bao-factory/BaoFactory.sol";
import {BaoFactory_v1} from "@bao-factory/BaoFactory_v1.sol";
import {BaoFactoryLib} from "@bao-factory/BaoFactoryLib.sol";
import {BaoFactoryBytecode} from "@bao-factory/BaoFactoryBytecode.sol";
import {IBaoFactory} from "@bao-factory/IBaoFactory.sol";
import {FundedVault, NonPayableVault, FundedVaultUUPS} from "./mocks/FundedVault.sol";
import {BaoFactoryV2, BaoFactoryNonUUPS} from "./mocks/BaoFactoryV2.sol";

/// @dev Simple contract used for deployment tests
contract SimpleContract {
    uint256 public value;
    address public deployer;

    constructor(uint256 _value) {
        value = _value;
        deployer = msg.sender;
    }
}

/// @title BaoFactoryTest
/// @notice Tests for the BaoFactory deterministic deployer
/// @dev Uses vm.prank to impersonate the hardcoded owner for privileged operations.
///      Setup deploys bootstrap BaoFactory, asserts it lacks IBaoFactory functions,
///      then upgrades to BaoFactory_v1 for operator/deploy functionality.
contract BaoFactoryTest is Test {
    IBaoFactory internal factory;
    BaoFactory internal bootstrap;
    address internal proxyAddr;
    address internal owner;
    address internal operator;
    address internal outsider;

    uint256 internal constant OPERATOR_DELAY = 1 days;

    function setUp() public {
        owner = BaoFactoryBytecode.OWNER;
        operator = makeAddr("operator");
        outsider = makeAddr("outsider");

        // Deploy bootstrap implementation (constructor also deploys proxy and emits event)
        vm.recordLogs();
        bootstrap = new BaoFactory();

        // Extract proxy address from BaoFactoryDeployed event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BaoFactory.BaoFactoryDeployed.selector) {
                proxyAddr = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(proxyAddr != address(0), "BaoFactoryDeployed event not found");

        // --- Assert bootstrap lacks IBaoFactory functionality ---
        // setOperator should not exist (call reverts with no data)
        (bool success, ) = proxyAddr.call(abi.encodeWithSelector(IBaoFactory.setOperator.selector, operator, 1 days));
        assertFalse(success, "bootstrap should not have setOperator");

        // deploy(bytes,bytes32) should not exist
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        (success, ) = proxyAddr.call(abi.encodeWithSignature("deploy(bytes,bytes32)", initCode, bytes32(0)));
        assertFalse(success, "bootstrap should not have deploy");

        // predictAddress should not exist
        (success, ) = proxyAddr.call(abi.encodeWithSelector(IBaoFactory.predictAddress.selector, bytes32(0)));
        assertFalse(success, "bootstrap should not have predictAddress");

        // operatorAt should not exist
        (success, ) = proxyAddr.call(abi.encodeWithSelector(IBaoFactory.operatorAt.selector, uint256(0)));
        assertFalse(success, "bootstrap should not have operatorAt");

        // isCurrentOperator should not exist
        (success, ) = proxyAddr.call(abi.encodeWithSelector(IBaoFactory.isCurrentOperator.selector, operator));
        assertFalse(success, "bootstrap should not have isCurrentOperator");

        // owner() should work on bootstrap (it has this function)
        (success, ) = proxyAddr.call(abi.encodeWithSelector(bytes4(keccak256("owner()"))));
        assertTrue(success, "bootstrap should have owner()");

        // --- Upgrade to BaoFactory_v1 ---
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        vm.prank(owner);
        UUPSUpgradeable(proxyAddr).upgradeToAndCall(address(v1Impl), "");

        factory = IBaoFactory(proxyAddr);

        // Set up an operator with 1 day expiry
        vm.prank(owner);
        factory.setOperator(operator, OPERATOR_DELAY);
    }

    /// @dev Enumerates operator entries via operatorAt by probing consecutive indexes until revert
    function _snapshotOperators(
        IBaoFactory target
    ) internal view returns (address[] memory addrs, uint256[] memory expiries) {
        uint256 count;
        while (true) {
            try target.operatorAt(count) returns (address, uint256) {
                unchecked {
                    ++count;
                }
            } catch {
                break;
            }
        }

        addrs = new address[](count);
        expiries = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            (addrs[i], expiries[i]) = target.operatorAt(i);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_ConstructorDeploysProxyAndEmitsEvent_() public {
        vm.recordLogs();
        BaoFactory impl = new BaoFactory();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        address eventProxy;
        address eventImpl;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BaoFactory.BaoFactoryDeployed.selector) {
                eventProxy = address(uint160(uint256(logs[i].topics[1])));
                eventImpl = address(uint160(uint256(logs[i].topics[2])));
                foundEvent = true;
                break;
            }
        }

        assertTrue(foundEvent, "BaoFactoryDeployed event not emitted");
        assertEq(eventImpl, address(impl), "Implementation address mismatch in event");
        assertTrue(eventProxy != address(0), "Proxy address should be non-zero");
        assertTrue(eventProxy.code.length > 0, "Proxy should have code");
    }

    function test_ProxyAddressPrediction_() public view {
        // Verify BaoFactoryLib.predictProxy matches actual deployment
        address predictedProxy = BaoFactoryLib.predictProxy(address(bootstrap));
        assertEq(proxyAddr, predictedProxy, "Proxy address prediction mismatch");
    }

    function test_OwnerIsHardcodedConstant_() public view {
        assertEq(factory.owner(), 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2, "owner mismatch");
        // Verify bootstrap returns same owner
        assertEq(bootstrap.owner(), factory.owner(), "bootstrap and proxy owner mismatch");
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OPERATOR MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_SetOperatorOnlyOwner_() public {
        address newOperator = makeAddr("new operator");

        vm.expectEmit(true, false, false, true);
        emit IBaoFactory.OperatorSet(newOperator, block.timestamp + OPERATOR_DELAY);

        vm.prank(owner);
        factory.setOperator(newOperator, OPERATOR_DELAY);

        assertTrue(factory.isCurrentOperator(newOperator), "new operator should be valid");
    }

    function test_SetOperatorRevertUnauthorized_() public {
        vm.prank(outsider);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        factory.setOperator(makeAddr("forbidden"), OPERATOR_DELAY);
    }

    function test_SetOperatorRevertInvalidDelay_() public {
        uint256 tooLongDelay = 100 * 52 weeks + 1;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IBaoFactory.InvalidDelay.selector, tooLongDelay));
        factory.setOperator(makeAddr("longterm"), tooLongDelay);
    }

    function test_RemoveOperator_() public {
        assertTrue(factory.isCurrentOperator(operator), "operator should be valid initially");

        vm.expectEmit(true, false, false, false);
        emit IBaoFactory.OperatorRemoved(operator);

        vm.prank(owner);
        factory.setOperator(operator, 0); // delay=0 removes

        assertFalse(factory.isCurrentOperator(operator), "operator should be removed");
    }

    function test_OperatorExpiry_() public {
        assertTrue(factory.isCurrentOperator(operator), "operator should be valid initially");

        // Warp past expiry
        vm.warp(block.timestamp + OPERATOR_DELAY + 1);

        assertFalse(factory.isCurrentOperator(operator), "operator should be expired");
    }

    function test_OperatorsEnumeration_() public {
        address op2 = makeAddr("operator2");
        address op3 = makeAddr("operator3");

        vm.prank(owner);
        factory.setOperator(op2, 2 days);

        vm.prank(owner);
        factory.setOperator(op3, 3 days);

        (address[] memory addrs, uint256[] memory expiries) = _snapshotOperators(factory);
        assertEq(addrs.length, 3, "should enumerate three operators before removals");
        assertEq(expiries.length, 3, "expiries array should align with operators array");

        bool foundPrimary;
        bool foundOp2;
        bool foundOp3;

        for (uint256 i = 0; i < addrs.length; ++i) {
            if (addrs[i] == operator) {
                foundPrimary = true;
                assertEq(expiries[i], block.timestamp + OPERATOR_DELAY, "primary operator expiry mismatch");
            } else if (addrs[i] == op2) {
                foundOp2 = true;
                assertEq(expiries[i], block.timestamp + 2 days, "op2 expiry mismatch");
            } else if (addrs[i] == op3) {
                foundOp3 = true;
                assertEq(expiries[i], block.timestamp + 3 days, "op3 expiry mismatch");
            }
        }

        assertTrue(foundPrimary, "primary operator not enumerated");
        assertTrue(foundOp2, "op2 not enumerated");
        assertTrue(foundOp3, "op3 not enumerated");

        vm.prank(owner);
        factory.setOperator(op2, 0);

        (addrs, expiries) = _snapshotOperators(factory);
        assertEq(addrs.length, 2, "removal should shrink operator array");
        assertEq(expiries.length, 2, "removal should shrink expiry array");

        for (uint256 i = 0; i < addrs.length; ++i) {
            assertTrue(addrs[i] != op2, "removed operator should not appear in enumeration");
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_OwnerCanDeploy_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(42)));
        bytes32 salt = keccak256("owner.deploy");
        address predicted = factory.predictAddress(salt);

        vm.prank(owner);
        address deployed = factory.deploy(initCode, salt);

        assertEq(deployed, predicted, "deployed address mismatch");
        SimpleContract simple = SimpleContract(deployed);
        assertEq(simple.value(), 42, "deployed contract value mismatch");
    }

    function test_OperatorCanDeploy_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(77)));
        bytes32 salt = keccak256("operator.deploy");
        address predicted = factory.predictAddress(salt);

        vm.prank(operator);
        address deployed = factory.deploy(initCode, salt);

        assertEq(deployed, predicted, "deployed address mismatch");
        SimpleContract simple = SimpleContract(deployed);
        assertEq(simple.value(), 77, "deployed contract value mismatch");
    }

    function test_DeployEmitsEvent_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(99)));
        bytes32 salt = keccak256("emit.deploy");
        address predicted = factory.predictAddress(salt);

        vm.expectEmit(true, true, false, true);
        emit IBaoFactory.Deployed(predicted, salt, 0);

        vm.prank(owner);
        factory.deploy(initCode, salt);
    }

    function test_DeployWithValue_() public {
        uint256 value = 2 ether;
        bytes memory initCode = type(FundedVault).creationCode;
        bytes32 salt = keccak256("value.deploy");

        vm.deal(owner, value);
        vm.prank(owner);
        address deployed = factory.deploy{value: value}(value, initCode, salt);

        FundedVault vault = FundedVault(payable(deployed));
        assertEq(address(vault).balance, value, "should transfer ETH to deployed contract");
        assertEq(vault.initialBalance(), value, "constructor should see funded value");
    }

    function test_DeployValueMismatchReverts_() public {
        uint256 declaredValue = 1 ether;
        bytes memory initCode = type(FundedVault).creationCode;
        bytes32 salt = keccak256("value.mismatch");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IBaoFactory.ValueMismatch.selector, declaredValue, 0));
        factory.deploy(declaredValue, initCode, salt);
    }

    function test_DeployRevertUnauthorized_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("unauthorized");

        vm.prank(outsider);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        factory.deploy(initCode, salt);
    }

    function test_ExpiredOperatorCannotDeploy_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("expired.operator");

        // Warp past operator expiry
        vm.warp(block.timestamp + OPERATOR_DELAY + 1);

        vm.prank(operator);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        factory.deploy(initCode, salt);
    }

    function test_ExpiredOperatorStillStoredCannotDeploy_() public {
        // Operator entry should exist before expiry
        (address addr, uint256 expiry) = factory.operatorAt(0);
        assertEq(addr, operator, "operator at index 0 mismatch");
        vm.expectRevert();
        factory.operatorAt(1);

        vm.warp(block.timestamp + OPERATOR_DELAY + 1);

        // Enumeration keeps expired operators, confirm timestamp is stale
        (addr, expiry) = factory.operatorAt(0);
        assertEq(addr, operator, "operator should still be enumerable");
        assertLt(expiry, block.timestamp, "expiry should be in the past");

        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(2)));
        bytes32 salt = keccak256("expired.operator.still.stored");

        vm.prank(operator);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        factory.deploy(initCode, salt);
    }

    function test_DeployProxyPayload_() public {
        FundedVaultUUPS vaultImpl = new FundedVaultUUPS(owner);
        // Use LibClone to create ERC1967 proxy initcode
        bytes memory proxyInit = LibClone.initCodeERC1967(address(vaultImpl));
        bytes32 salt = keccak256("uups.proxy");

        vm.prank(owner);
        address deployed = factory.deploy(proxyInit, salt);

        // Initialize the proxy after deployment
        FundedVaultUUPS proxy = FundedVaultUUPS(payable(deployed));
        proxy.initialize();
        assertTrue(address(proxy) != address(0), "proxy should be deployed");
        assertEq(proxy.owner(), owner, "proxy owner mismatch");
    }

    function test_DeployNonPayableTargetReverts_() public {
        uint256 value = 1 ether;
        bytes memory initCode = abi.encodePacked(type(NonPayableVault).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("nonpayable");

        vm.deal(owner, value);
        vm.prank(owner);
        vm.expectRevert();
        factory.deploy{value: value}(value, initCode, salt);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            ADDRESS PREDICTION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_PredictAddressIndependentOfInitCode_() public {
        bytes32 salt = keccak256("prediction.test");
        address predicted = factory.predictAddress(salt);

        // Deploy with one initCode
        bytes memory initCode1 = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        vm.prank(owner);
        address deployed = factory.deploy(initCode1, salt);

        assertEq(deployed, predicted, "deployed address should match prediction");
    }

    function test_MultipleDeploymentsHaveDifferentAddresses_() public {
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        bytes32 salt1 = keccak256("deploy.1");
        bytes32 salt2 = keccak256("deploy.2");

        vm.startPrank(owner);
        address addr1 = factory.deploy(initCode, salt1);
        address addr2 = factory.deploy(initCode, salt2);
        vm.stopPrank();

        assertTrue(addr1 != addr2, "same initCode with different salts should give different addresses");
    }

    /*//////////////////////////////////////////////////////////////////////////
                           BAOFACTORYLIB TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_BaoFactoryLibPredictImplementation_() public pure {
        bytes32 mockCreationCodeHash = keccak256("mock.creation.code");
        string memory salt = BaoFactoryBytecode.SALT;
        address predicted = BaoFactoryLib.predictImplementation(salt, mockCreationCodeHash);

        // Verify CREATE2 address formula
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), BaoFactoryLib.NICKS_FACTORY, keccak256(bytes(salt)), mockCreationCodeHash)
        );
        address expected = address(uint160(uint256(hash)));
        assertEq(predicted, expected, "implementation prediction formula mismatch");
    }

    function test_BaoFactoryLibPredictAddresses_() public pure {
        bytes32 mockCreationCodeHash = keccak256("mock.creation.code");
        string memory salt = BaoFactoryBytecode.SALT;
        (address impl, address proxy) = BaoFactoryLib.predictAddresses(salt, mockCreationCodeHash);

        assertEq(impl, BaoFactoryLib.predictImplementation(salt, mockCreationCodeHash), "impl prediction mismatch");
        assertEq(proxy, BaoFactoryLib.predictProxy(impl), "proxy prediction mismatch");
    }

    /*//////////////////////////////////////////////////////////////////////////
                              UUPS UPGRADE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_UpgradeToV2MaintainsProxyAddress_() public {
        address proxyBefore = address(factory);

        // Deploy V2 implementation
        BaoFactoryV2 v2Impl = new BaoFactoryV2();

        // Upgrade via owner
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Proxy address should be unchanged
        assertEq(address(factory), proxyBefore, "proxy address should not change after upgrade");

        // Should now report version 2
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        assertEq(upgraded.version(), 2, "should be version 2 after upgrade");
    }

    function test_UpgradeRetainsOperatorState_() public {
        // Set up an operator before upgrade
        address testOperator = makeAddr("testOperator");
        vm.prank(owner);
        factory.setOperator(testOperator, 7 days);
        assertTrue(factory.isCurrentOperator(testOperator), "operator should be valid before upgrade");

        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Operator should still be valid after upgrade
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        assertTrue(upgraded.isCurrentOperator(testOperator), "operator should still be valid after upgrade");

        // Verify we can still enumerate operators
        (address[] memory addrs, ) = _snapshotOperators(IBaoFactory(address(upgraded)));
        assertEq(addrs.length, 2, "should have 2 operators (original + testOperator)");
    }

    function test_UpgradeUnauthorizedReverts_() public {
        BaoFactoryV2 v2Impl = new BaoFactoryV2();

        // Non-owner cannot upgrade
        vm.prank(outsider);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Operator cannot upgrade (only owner can)
        vm.prank(operator);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");
    }

    function test_UpgradeToNonUUPSReverts_() public {
        BaoFactoryNonUUPS nonUupsImpl = new BaoFactoryNonUUPS();

        // Attempt to upgrade to non-UUPS implementation should revert
        vm.prank(owner);
        vm.expectRevert(UUPSUpgradeable.UpgradeFailed.selector);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(nonUupsImpl), "");
    }

    function test_UpgradeWithInitializationCall_() public {
        BaoFactoryV2 v2Impl = new BaoFactoryV2();

        // Upgrade and call version() in the same transaction
        bytes memory initData = abi.encodeCall(BaoFactoryV2.version, ());

        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), initData);

        // Should be upgraded
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        assertEq(upgraded.version(), 2, "should be version 2");
    }

    function test_UpgradedContractCanStillDeploy_() public {
        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Deploy via upgraded factory
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(123)));
        bytes32 salt = keccak256("v2.deploy");
        address predicted = upgraded.predictAddress(salt);

        vm.prank(owner);
        address deployed = upgraded.deploy(initCode, salt);

        assertEq(deployed, predicted, "deployed address should match prediction");
        assertEq(SimpleContract(deployed).value(), 123, "deployed contract should work");
    }

    /// @notice Deploying with same salt after upgrade should fail (CREATE3 collision)
    /// @dev The proxy address is preserved across upgrades, so CREATE3 addresses remain constant.
    ///      Reusing a salt that was used pre-upgrade must fail.
    function test_DeploySameSaltAfterUpgradeReverts_() public {
        bytes32 salt = keccak256("pre.upgrade.salt");
        bytes memory initCode1 = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(100)));

        // Deploy before upgrade
        vm.prank(owner);
        address deployed1 = factory.deploy(initCode1, salt);
        assertTrue(deployed1 != address(0), "first deployment should succeed");

        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Attempt to deploy with same salt after upgrade - should revert
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        bytes memory initCode2 = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(200)));

        vm.prank(owner);
        vm.expectRevert();
        upgraded.deploy(initCode2, salt);
    }

    /// @notice Predicted address remains constant across upgrades
    /// @dev Since the proxy address doesn't change, predictAddress should return the same value
    function test_PredictAddressConsistentAcrossUpgrades_() public {
        bytes32 salt = keccak256("consistent.prediction");

        // Predict before upgrade
        address predictedBefore = factory.predictAddress(salt);

        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Predict after upgrade
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        address predictedAfter = upgraded.predictAddress(salt);

        assertEq(predictedBefore, predictedAfter, "predicted address should be consistent across upgrades");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SECURITY ATTACK VECTOR TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test: Implementation cannot be called directly for privileged ops
    /// @dev The implementation has same owner constant but calling deploy() directly
    ///      would bypass the proxy pattern. The key is that deployed contracts from
    ///      impl would have different addresses than proxy deployments.
    function test_ImplementationDirectCallsHaveDifferentAddresses_() public {
        // Deploy a fresh v1 implementation to test against
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        bytes32 salt = keccak256("direct.vs.proxy");

        // Predict address from proxy (the canonical factory)
        address proxyPredicted = factory.predictAddress(salt);

        // Predict address from implementation (would be different CREATE3 deployer)
        address implPredicted = v1Impl.predictAddress(salt);

        // Different deployers (proxy vs implementation) produce different addresses
        assertTrue(
            proxyPredicted != implPredicted,
            "implementation and proxy should produce different addresses for same salt"
        );
    }

    /// @notice Test: Verify Nick's Factory produces deterministic addresses
    /// @dev The BaoFactory proxy address is deterministic based on impl address
    function test_NicksFactoryDeploymentIsDeterministic_() public pure {
        // Get the creation code hash for BaoFactory
        bytes32 creationCodeHash = keccak256(type(BaoFactory).creationCode);
        string memory salt = BaoFactoryBytecode.SALT;

        // Predict addresses using the library
        (address predictedImpl, address predictedProxy) = BaoFactoryLib.predictAddresses(salt, creationCodeHash);

        // These should be constant across runs (same salt + same initcode = same address)
        assertEq(
            BaoFactoryLib.predictImplementation(salt, creationCodeHash),
            predictedImpl,
            "implementation prediction should be consistent"
        );
        assertEq(BaoFactoryLib.predictProxy(predictedImpl), predictedProxy, "proxy prediction should be consistent");
    }

    /// @notice Test: Removed operator cannot deploy
    function test_RemovedOperatorCannotDeploy_() public {
        // Verify operator can deploy initially
        assertTrue(factory.isCurrentOperator(operator), "operator should be valid initially");

        // Remove the operator (delay=0)
        vm.prank(owner);
        factory.setOperator(operator, 0);
        assertFalse(factory.isCurrentOperator(operator), "operator should be removed");

        // Attempt to deploy should fail
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("removed.operator");

        vm.prank(operator);
        vm.expectRevert(IBaoFactory.Unauthorized.selector);
        factory.deploy(initCode, salt);
    }

    /// @notice Test: Deploying same salt twice reverts (CREATE3 collision)
    /// @dev CREATE3 uses CREATE2 to deploy a proxy that does CREATE for the actual contract.
    ///      Same salt means same CREATE2 address for proxy, which will fail on redeployment.
    function test_DeploySameSaltTwiceReverts_() public {
        bytes memory initCode1 = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        bytes memory initCode2 = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(2)));
        bytes32 salt = keccak256("collision.test");

        // First deployment succeeds
        vm.prank(owner);
        address deployed = factory.deploy(initCode1, salt);
        assertTrue(deployed != address(0), "first deployment should succeed");

        // Second deployment with same salt should revert (regardless of initCode)
        vm.prank(owner);
        vm.expectRevert();
        factory.deploy(initCode2, salt);
    }

    /*//////////////////////////////////////////////////////////////////////////
                           BOOTSTRAP-SPECIFIC TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test: Bootstrap can only be upgraded by owner
    function test_BootstrapUpgradeOnlyOwner_() public {
        // Deploy fresh bootstrap
        vm.recordLogs();
        new BaoFactory();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address freshProxyAddr;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BaoFactory.BaoFactoryDeployed.selector) {
                freshProxyAddr = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }

        BaoFactory_v1 v1Impl = new BaoFactory_v1();

        // Outsider cannot upgrade
        vm.prank(outsider);
        vm.expectRevert(BaoFactory.Unauthorized.selector);
        UUPSUpgradeable(freshProxyAddr).upgradeToAndCall(address(v1Impl), "");

        // Owner can upgrade
        vm.prank(owner);
        UUPSUpgradeable(freshProxyAddr).upgradeToAndCall(address(v1Impl), "");

        // Verify upgrade worked
        assertFalse(IBaoFactory(freshProxyAddr).isCurrentOperator(address(0)), "upgrade should work");
    }

    /// @notice Test: Bootstrap rejects upgrade to zero address
    function test_BootstrapUpgradeToZeroAddressReverts_() public {
        // Deploy fresh bootstrap
        vm.recordLogs();
        new BaoFactory();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address freshProxyAddr;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BaoFactory.BaoFactoryDeployed.selector) {
                freshProxyAddr = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }

        // Attempt to upgrade to zero address
        vm.prank(owner);
        vm.expectRevert(BaoFactory.InvalidAddress.selector);
        UUPSUpgradeable(freshProxyAddr).upgradeToAndCall(address(0), "");
    }

    /// @notice Test: Multiple sequential upgrades work correctly
    function test_MultipleSequentialUpgrades_() public {
        // Already upgraded to v1 in setUp, now upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        assertEq(upgraded.version(), 2, "should be v2");

        // Downgrade back to v1 (allowed since both are UUPS)
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        vm.prank(owner);
        upgraded.upgradeToAndCall(address(v1Impl), "");

        // Verify it still works
        assertTrue(factory.isCurrentOperator(operator), "operator should still be valid after downgrade");
    }

    /// @notice Test: Operator state persists through multiple upgrades
    function test_OperatorStatePersistsThroughMultipleUpgrades_() public {
        address persistentOp = makeAddr("persistentOp");

        // Add operator in v1
        vm.prank(owner);
        factory.setOperator(persistentOp, 30 days);
        assertTrue(factory.isCurrentOperator(persistentOp), "operator should be valid in v1");

        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        assertTrue(upgraded.isCurrentOperator(persistentOp), "operator should be valid in v2");

        // Downgrade to v1
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        vm.prank(owner);
        upgraded.upgradeToAndCall(address(v1Impl), "");

        assertTrue(factory.isCurrentOperator(persistentOp), "operator should be valid after downgrade");
    }

    /// @notice Test: Deployments before and after upgrade use consistent address space
    function test_DeploymentAddressSpaceConsistentAcrossUpgrades_() public {
        bytes32 salt1 = keccak256("before.upgrade");
        bytes32 salt2 = keccak256("after.upgrade");

        // Predict both addresses before upgrade
        address predicted1 = factory.predictAddress(salt1);
        address predicted2 = factory.predictAddress(salt2);

        // Deploy first contract
        bytes memory initCode = abi.encodePacked(type(SimpleContract).creationCode, abi.encode(uint256(1)));
        vm.prank(owner);
        address deployed1 = factory.deploy(initCode, salt1);
        assertEq(deployed1, predicted1, "pre-upgrade deployment address mismatch");

        // Upgrade to V2
        BaoFactoryV2 v2Impl = new BaoFactoryV2();
        vm.prank(owner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2Impl), "");

        // Deploy second contract after upgrade
        BaoFactoryV2 upgraded = BaoFactoryV2(address(factory));
        vm.prank(owner);
        address deployed2 = upgraded.deploy(initCode, salt2);
        assertEq(deployed2, predicted2, "post-upgrade deployment address mismatch");
    }
}
