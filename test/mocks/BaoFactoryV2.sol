// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {CREATE3} from "@solady/utils/CREATE3.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {EnumerableMapLib} from "@solady/utils/EnumerableMapLib.sol";

/// @title BaoFactoryV2
/// @notice Mock V2 of BaoFactory for testing UUPS upgrades
/// @dev Adds a version() function to verify the upgrade took effect
contract BaoFactoryV2 is UUPSUpgradeable {
    using EnumerableMapLib for EnumerableMapLib.AddressToUint256Map;

    /*//////////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error ValueMismatch(uint256 expected, uint256 received);

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Immutable owner address (same as V1)
    address public constant OWNER = 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2;

    /*//////////////////////////////////////////////////////////////////////////
                                   STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev ERC-7201 namespace slot - must match BaoFactory_v1
    bytes32 private constant _BAO_FACTORY_STORAGE = 0x46346a24345285b46a89a0cbc81552c1509a45bd5b640b2cdd7167d1559d8300;

    struct BaoFactoryStorage {
        EnumerableMapLib.AddressToUint256Map operators;
    }

    function _storage() private pure returns (BaoFactoryStorage storage $) {
        bytes32 position = _BAO_FACTORY_STORAGE;
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event OperatorSet(address indexed operator, uint40 expiry);
    event OperatorRemoved(address indexed operator);
    event Deployed(address indexed deployed, bytes32 indexed salt, uint256 value);
    event BaoFactoryDeployed(address indexed proxy, address indexed implementation);

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice V2 constructor - does NOT deploy a proxy (upgrade, not fresh deploy)
    /// @dev When upgrading, we don't want a new proxy - we keep the existing one
    constructor() {
        // No proxy deployment - this is for upgrades only
    }

    /*//////////////////////////////////////////////////////////////////////////
                              NEW V2 FUNCTIONALITY
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the contract version
    /// @dev This is the new functionality added in V2 to verify upgrade worked
    function version() external pure returns (uint256) {
        return 2;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    function setOperator(address operator_, uint256 delay) external onlyOwner {
        BaoFactoryStorage storage $ = _storage();
        if (delay == 0) {
            $.operators.remove(operator_);
            emit OperatorRemoved(operator_);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint40 expiry = uint40(block.timestamp + delay);
            $.operators.set(operator_, expiry);
            emit OperatorSet(operator_, expiry);
        }
    }

    function operators() external view returns (address[] memory addrs, uint40[] memory expiries) {
        BaoFactoryStorage storage $ = _storage();
        uint256 len = $.operators.length();
        addrs = new address[](len);
        expiries = new uint40[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 rawExpiry;
            (addrs[i], rawExpiry) = $.operators.at(i);
            // forge-lint: disable-next-line(unsafe-typecast)
            expiries[i] = uint40(rawExpiry);
        }
    }

    function operatorAt(uint256 index) external view returns (address operator, uint256 expiry) {
        BaoFactoryStorage storage $ = _storage();
        (operator, expiry) = $.operators.at(index);
    }

    function isCurrentOperator(address addr) external view returns (bool) {
        BaoFactoryStorage storage $ = _storage();
        (bool exists, uint256 expiry) = $.operators.tryGet(addr);
        return exists && expiry > block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  DEPLOYMENT
    //////////////////////////////////////////////////////////////////////////*/

    function deploy(bytes memory initCode, bytes32 salt) external onlyOwnerOrOperator returns (address deployed) {
        deployed = CREATE3.deployDeterministic(initCode, salt);
        emit Deployed(deployed, salt, 0);
    }

    function deploy(
        uint256 value,
        bytes memory initCode,
        bytes32 salt
    ) external payable onlyOwnerOrOperator returns (address deployed) {
        if (msg.value != value) {
            revert ValueMismatch(value, msg.value);
        }
        deployed = CREATE3.deployDeterministic(value, initCode, salt);
        emit Deployed(deployed, salt, value);
    }

    function predictAddress(bytes32 salt) external view returns (address predicted) {
        predicted = CREATE3.predictDeterministicAddress(salt);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  UUPS UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal view override onlyOwner {}

    /*//////////////////////////////////////////////////////////////////////////
                                  MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyOwnerOrOperator() {
        if (msg.sender != OWNER) {
            BaoFactoryStorage storage $ = _storage();
            (bool exists, uint256 expiry) = $.operators.tryGet(msg.sender);
            if (!exists || expiry <= block.timestamp) {
                revert Unauthorized();
            }
        }
        _;
    }
}

/// @title BaoFactoryNonUUPS
/// @notice Mock contract that is NOT UUPS-compliant for testing upgrade rejection
/// @dev Missing proxiableUUID() - upgrade should fail
contract BaoFactoryNonUUPS {
    address public constant OWNER = 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2;

    function version() external pure returns (uint256) {
        return 99;
    }
}
