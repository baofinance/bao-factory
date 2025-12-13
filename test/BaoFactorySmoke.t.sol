// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {BaoFactory} from "@bao-factory/BaoFactory.sol";
import {BaoFactoryLib} from "@bao-factory/BaoFactoryLib.sol";
import {BaoFactoryBytecode} from "@bao-factory/BaoFactoryBytecode.sol";
import {FundedVault, NonPayableVault} from "./mocks/FundedVault.sol";

/// @title BaoFactorySmokeTest
/// @notice Minimal harness that simply exercises the primary BaoFactory entrypoints
contract BaoFactorySmokeTest is Test {
    BaoFactory internal factory;
    address internal owner = BaoFactoryBytecode.OWNER;
    address internal operator = makeAddr("smoke-operator");

    function setUp() public {
        BaoFactory implementation = new BaoFactory();
        address proxyAddr = BaoFactoryLib.predictProxy(address(implementation));
        factory = BaoFactory(payable(proxyAddr));
    }

    function testSmokeSetOperator() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);
    }

    function testSmokeDeployBare() public {
        bytes memory initCode = abi.encodePacked(type(NonPayableVault).creationCode, abi.encode(uint256(1)));
        bytes32 salt = keccak256("smoke.bare");

        vm.prank(owner);
        factory.deploy(initCode, salt);
    }

    function testSmokeDeployWithValue() public {
        uint256 value = 0.25 ether;
        bytes memory initCode = type(FundedVault).creationCode;
        bytes32 salt = keccak256("smoke.value");

        vm.deal(owner, value);
        vm.prank(owner);
        factory.deploy{value: value}(value, initCode, salt);
    }

    function testSmokeOperatorsView() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);
        factory.operatorAt(0);
    }

    function testSmokeOperatorDeploy() public {
        vm.prank(owner);
        factory.setOperator(operator, 1 days);

        bytes memory initCode = abi.encodePacked(type(NonPayableVault).creationCode, abi.encode(uint256(2)));
        bytes32 salt = keccak256("smoke.operator");

        vm.prank(operator);
        factory.deploy(initCode, salt);
    }
}
