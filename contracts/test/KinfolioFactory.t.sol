// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {KinfolioFactory} from "../src/KinfolioFactory.sol";
import {KinfolioTrust} from "../src/KinfolioTrust.sol";
import {IKinfolioFactory} from "../src/interfaces/IKinfolioFactory.sol";
import {IKinfolioTrust} from "../src/interfaces/IKinfolioTrust.sol";
import {KinfolioBase} from "./utils/KinfolioBase.sol";

contract KinfolioFactoryTest is KinfolioBase {
    function test_CreateTrust_DeploysAtPredictedAddress() public {
        address predicted = factory.predictTrust(owner, bytes32(0));

        vm.expectEmit(true, true, false, false, address(factory));
        emit IKinfolioFactory.TrustCreated(owner, predicted);
        KinfolioTrust trust = _createFamilyTrust();

        assertEq(address(trust), predicted);
        assertTrue(factory.isTrust(predicted));
        assertEq(factory.trustsOf(owner).length, 1);
        assertEq(factory.trustsOf(owner)[0], predicted);
    }

    function test_CreateTrust_IndexesEachBeneficiaryOnce() public {
        KinfolioTrust trust = _createFamilyTrust();

        assertEq(factory.trustsFor(spouse)[0], address(trust));
        assertEq(factory.trustsFor(parent)[0], address(trust));
        // child holds two grants but is indexed once
        assertEq(factory.trustsFor(child).length, 1);
        assertEq(factory.trustsFor(stranger).length, 0);
    }

    function test_CreateTrust_SaltIsScopedToCaller() public view {
        assertTrue(
            factory.predictTrust(owner, bytes32(0)) != factory.predictTrust(spouse, bytes32(0))
        );
        assertTrue(
            factory.predictTrust(owner, bytes32(0))
                != factory.predictTrust(owner, bytes32(uint256(1)))
        );
    }

    function test_RevertWhen_SameOwnerReusesSalt() public {
        _createFamilyTrust();
        IKinfolioTrust.TrustConfig memory config = _config(_assets(), _familyGrants());
        vm.prank(owner);
        vm.expectRevert();
        factory.createTrust(config, bytes32(0));
    }

    function test_RevertWhen_InitializingImplementation() public {
        KinfolioTrust impl = KinfolioTrust(factory.IMPLEMENTATION());
        IKinfolioTrust.TrustConfig memory config = _config(_assets(), _familyGrants());
        vm.prank(address(factory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(owner, config);
    }

    function test_RevertWhen_InitializingTwice() public {
        KinfolioTrust trust = _createFamilyTrust();
        IKinfolioTrust.TrustConfig memory config = _config(_assets(), _familyGrants());
        vm.prank(address(factory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        trust.initialize(stranger, config);
    }

    function test_RevertWhen_CloneInitializedByNonFactory() public {
        KinfolioTrust rogue = KinfolioTrust(Clones.clone(factory.IMPLEMENTATION()));
        IKinfolioTrust.TrustConfig memory config = _config(_assets(), _familyGrants());
        vm.prank(stranger);
        vm.expectRevert(IKinfolioTrust.NotFactory.selector);
        rogue.initialize(stranger, config);
    }

    function test_RevertWhen_NonTrustWritesIndex() public {
        address[] memory list = new address[](1);
        list[0] = stranger;
        vm.prank(stranger);
        vm.expectRevert(IKinfolioFactory.NotTrust.selector);
        factory.indexBeneficiaries(list);
    }

    function test_ImplementationCarriesDeploymentProfile() public view {
        KinfolioTrust impl = KinfolioTrust(factory.IMPLEMENTATION());
        assertEq(impl.FACTORY(), address(factory));
        assertEq(impl.CASH_ASSET(), address(usdg));
        assertEq(impl.MIN_INACTIVITY(), MIN_INACTIVITY);
        assertEq(impl.MIN_CHALLENGE(), MIN_CHALLENGE);
        assertEq(impl.owner(), address(0));
    }

    function test_RevertWhen_DeployingWithBadProfile() public {
        vm.expectRevert(IKinfolioTrust.ZeroAddress.selector);
        new KinfolioFactory(address(0), MIN_INACTIVITY, MIN_CHALLENGE);

        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        new KinfolioFactory(address(usdg), 0, MIN_CHALLENGE);

        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        new KinfolioFactory(address(usdg), MIN_INACTIVITY, 366 days);
    }
}
