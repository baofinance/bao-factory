// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";

import {BaoFactory} from "@bao-factory/BaoFactory.sol";
import {BaoFactory_v1} from "@bao-factory/BaoFactory_v1.sol";
import {BaoFactoryLib} from "@bao-factory/BaoFactoryLib.sol";
import {BaoFactoryBytecode} from "@bao-factory/BaoFactoryBytecode.sol";
import {IBaoFactory} from "@bao-factory/IBaoFactory.sol";
import {FundedVault, NonPayableVault} from "./mocks/FundedVault.sol";

/// @title BaoFactorySmokeTest
/// @notice Minimal harness that exercises the primary BaoFactory entrypoints
/// @dev Deploys bootstrap, upgrades to v1, then exercises IBaoFactory methods
contract BaoFactorySmokeTest is Test {
    IBaoFactory internal factory;
    address internal owner = BaoFactoryBytecode.OWNER;
    address internal operator = makeAddr("smoke-operator");

    function setUp() public {
        // Deploy bootstrap
        BaoFactory implementation = new BaoFactory();
        address proxyAddr = BaoFactoryLib.predictProxy(address(implementation));

        // Upgrade to v1
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        vm.prank(owner);
        UUPSUpgradeable(proxyAddr).upgradeToAndCall(address(v1Impl), "");

        factory = IBaoFactory(proxyAddr);
    }

    function testSmokeSetOperator_() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);
    }

    function testSmokeDeployBare_() public {
        bytes memory initCode = abi.encodePacked(type(NonPayableVault).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("smoke.bare");

        vm.prank(owner);
        factory.deploy(initCode, salt);
    }

    function testSmokeDeployWithValue_() public {
        uint256 value = 0.25 ether;
        bytes memory initCode = type(FundedVault).creationCode;
        bytes32 salt = keccak256("smoke.value");

        vm.deal(owner, value);
        vm.prank(owner);
        factory.deploy{value: value}(value, initCode, salt);
    }

    function testSmokeOperatorsView_() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);
        factory.operatorAt(0);
    }

    function testSmokeOperatorDeploy_() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);

        bytes memory initCode = abi.encodePacked(type(NonPayableVault).creationCode, abi.encode(uint256(2)));
        bytes32 salt = keccak256("smoke.operator");

        vm.prank(operator);
        factory.deploy(initCode, salt);
    }
}
