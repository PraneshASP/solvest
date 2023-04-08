// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/StdStorage.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../src/Vest.sol";

contract MockVest is Vest, Test {
    using stdStorage for StdStorage;

    address internal immutable _token;

    constructor(address token) Vest() {
        _token = token;
    }

    function validateId(uint256 id) external view {
        _validateId(id);
    }

    function unclaimed(uint256 id) external view returns (uint256) {
        return _unclaimed(id);
    }

    function _transfer(address receiver, uint256 amount) internal override {
        stdstore.target(_token).sig("balanceOf(address)").with_key(receiver).checked_write(amount);
    }
}

contract VestTest is Test {
    using stdStorage for StdStorage;

    event VestingCreated(uint256 id, address receiver);
    event VestingRevoked(uint256 id, uint256 end);
    event Claimed(uint256 id, uint256 amount);
    event VestingProtected(uint256 id);
    event VestingUnprotected(uint256 id);
    event VestingRestricted(uint256 id);
    event VestingUnrestricted(uint256 id);
    event ReceiverSet(uint256 id, address receiver);

    uint256 internal immutable START;
    uint256 internal constant TWENTY_YEARS = 20 * 365 days;
    uint256 internal constant OFFSET = 1_000;
    uint256 internal constant TOTAL = 1_000;
    uint256 internal constant DURATION = 3 * 365 days;

    MockVest internal vest;
    ERC20 internal token;

    address alice = address(0x1);
    address bob = address(0x2);

    constructor() {
        START = block.timestamp + 30 days;
    }

    function setUp() public {
        token = new MockERC20("Test", "TST", 18);
        vest = new MockVest(address(token));

        vm.warp(TWENTY_YEARS + OFFSET);
    }

    function testOwner() public {
        assertEq(vest.owner(), address(this));
    }

    function testCreate(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        vm.expectEmit(true, true, true, true);
        emit VestingCreated(1, receiver);
        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(id, 1);
        assertEq(vesting.receiver, receiver);
        assertEq(vesting.start, start);
        assertEq(vesting.cliff, start + cliff);
        assertEq(vesting.end, start + duration);
        assertEq(vesting.manager, manager);
        assertEq(vesting.restricted, restricted);
        assertEq(vesting.protected, protected);
        assertEq(vesting.total, total);
        assertEq(vesting.claimed, 0);
    }

    function testCreateShouldRevertWhenCalledByNotOwner(
        address caller,
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(caller != address(this));
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.prank(caller);
        vm.expectRevert("UNAUTHORIZED");
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenReceiverIsZero(
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.AddressIsZero.selector);
        vest.create(address(0), start, cliff, duration, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenTotalIsZero(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);

        vm.expectRevert(Vest.TotalIsZero.selector);
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, 0);
    }

    function testCreateShouldRevertWhenStartIsTooFar(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, block.timestamp + TWENTY_YEARS + OFFSET, type(uint48).max);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.StartTooFar.selector);
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenStartTooLongAgo(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, 0, block.timestamp - TWENTY_YEARS - 1);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.StartTooLongAgo.selector);
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenDurationIsZero(
        address receiver,
        uint256 start,
        uint256 cliff,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.DurationIsZero.selector);
        vest.create(receiver, start, cliff, 0, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenDurationIsTooLong(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, 0, TWENTY_YEARS);
        duration = bound(duration, TWENTY_YEARS + 1, type(uint48).max);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.DurationTooLong.selector);
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);
    }

    function testCreateShouldRevertWhenCliffIsTooLong(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        cliff = bound(cliff, TWENTY_YEARS + 1, type(uint48).max);
        duration = bound(duration, 1, TWENTY_YEARS);
        total = bound(total, 1, type(uint128).max);

        vm.expectRevert(Vest.CliffTooLong.selector);
        vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);
    }

    function testValidateId(uint256 ids, uint256 id) public {
        ids = bound(ids, 1, type(uint256).max);
        id = bound(id, 0, ids - 1);
        stdstore.target(address(vest)).sig("ids()").checked_write(ids);

        vest.validateId(id);
    }

    function testValidateIdShouldRevertIfIdStrictlySuperiorToIds(uint256 ids, uint256 id) public {
        ids = bound(ids, 0, type(uint256).max - 1);
        id = bound(id, ids + 1, type(uint256).max);
        stdstore.target(address(vest)).sig("ids()").checked_write(ids);

        vm.expectRevert(Vest.InvalidVestingId.selector);
        vest.validateId(id);
    }

    function testClaimShouldFailWhenCalledByNotReceiverAndNoManagerSet(
        address caller,
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(caller != receiver);
        vm.assume(caller != manager);
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        vm.prank(caller);
        vm.expectRevert(Vest.PermissionDenied.selector);
        vest.claim(id);
    }

    function testClaimShouldFailWhenCalledByNotReceiverAndNotManagerButManagerSet(
        address caller,
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(caller != receiver);
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        vm.prank(caller);
        vm.expectRevert(Vest.PermissionDenied.selector);
        vest.claim(id);
    }

    function testClaimShouldFailWhenCalledByRestrictedManager(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(manager != receiver);
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, true, protected, total);

        vm.prank(manager);
        vm.expectRevert(Vest.PermissionDenied.selector);
        vest.claim(id);
    }

    function testClaimCalledByReceiver(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));

        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        vm.prank(receiver);
        vest.claim(id);
    }

    function testClaimCalledByManagerNotRestricted(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool protected,
        uint256 total
    ) public {
        vm.assume(receiver != address(0));

        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, false, protected, total);

        vm.prank(manager);
        vest.claim(id);
    }

    function testSetReceiver(address receiver) public {
        vm.assume(receiver != address(0));

        uint256 id = _createVest();

        vm.prank(alice);
        vest.setReceiver(id, receiver);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.receiver, receiver);
    }

    function testSetReceiverShouldFailWhenAddressZero() public {
        uint256 id = _createVest();

        vm.prank(alice);
        vm.expectRevert(Vest.AddressIsZero.selector);
        vest.setReceiver(id, address(0));
    }

    function testSetReceiverShouldFailWhenCalledByNotReceiver(address caller, address receiver) public {
        vm.assume(caller != alice);
        vm.assume(receiver != address(0));

        uint256 id = _createVest();

        vm.prank(caller);
        vm.expectRevert(Vest.OnlyReceiver.selector);
        vest.setReceiver(id, address(0));
    }

    function testProtect() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingProtected(id);

        vest.protect(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertTrue(vesting.protected);
    }

    function testProtectShouldFailWhenCalledByNotOwner(address caller) public {
        vm.assume(caller != vest.owner());

        uint256 id = _createVest();

        vm.prank(caller);
        vm.expectRevert("UNAUTHORIZED");
        vest.protect(id);
    }

    function testProtectShouldFailWhenInvalidId(uint256 id) public {
        id = bound(id, 2, type(uint256).max);

        _createVest();

        vm.expectRevert(Vest.InvalidVestingId.selector);
        vest.protect(id);
    }

    function testUnprotect() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingUnprotected(id);

        vest.unprotect(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertFalse(vesting.protected);
    }

    function testUnrotectShouldFailWhenCalledByNotOwner(address caller) public {
        vm.assume(caller != vest.owner());

        uint256 id = _createVest();

        vm.prank(caller);
        vm.expectRevert("UNAUTHORIZED");
        vest.unprotect(id);
    }

    function testUnprotectShouldFailWhenInvalidId(uint256 id) public {
        id = bound(id, 2, type(uint256).max);

        _createVest();

        vm.expectRevert(Vest.InvalidVestingId.selector);
        vest.unprotect(id);
    }

    function testRestrictCalledByOwner() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingRestricted(id);

        vest.restrict(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertTrue(vesting.restricted);
    }

    function testRestrictCalledByReceiver() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingRestricted(id);

        vm.prank(alice);
        vest.restrict(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertTrue(vesting.restricted);
    }

    function testRestrictShouldFailWhenCalledByNotOwnerNorReceiver(address caller) public {
        vm.assume(caller != vest.owner());
        vm.assume(caller != alice);

        uint256 id = _createVest();

        vm.prank(caller);
        vm.expectRevert(Vest.PermissionDenied.selector);
        vest.restrict(id);
    }

    function testRestrictShouldFailWhenInvalidId(uint256 id) public {
        id = bound(id, 2, type(uint256).max);

        _createVest();

        vm.expectRevert(Vest.InvalidVestingId.selector);
        vest.restrict(id);
    }

    function testUnrestrictCalledByOwner() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingUnrestricted(id);

        vest.unrestrict(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertFalse(vesting.restricted);
    }

    function testUnrestrictCalledByReceiver() public {
        uint256 id = _createVest();

        vm.expectEmit(true, true, true, true);
        emit VestingUnrestricted(id);

        vm.prank(alice);
        vest.unrestrict(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertFalse(vesting.restricted);
    }

    function testUnrestrictShouldFailWhenCalledByNotOwnerNorReceiver(address caller) public {
        vm.assume(caller != vest.owner());
        vm.assume(caller != alice);

        uint256 id = _createVest();

        vm.prank(caller);
        vm.expectRevert(Vest.PermissionDenied.selector);
        vest.unrestrict(id);
    }

    function testUnrestrictShouldFailWhenInvalidId(uint256 id) public {
        id = bound(id, 2, type(uint256).max);

        _createVest();

        vm.expectRevert(Vest.InvalidVestingId.selector);
        vest.unrestrict(id);
    }

    function testClaimBeforeCliff(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total,
        uint256 claimTime
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        claimTime = bound(claimTime, 0, start + cliff - 1);
        total = bound(total, 1, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        vm.warp(claimTime);

        vm.prank(receiver);
        vest.claim(id);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.claimed, 0);
    }

    function testClaimAfterCliff(
        address receiver,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        address manager,
        bool restricted,
        bool protected,
        uint256 total,
        uint256 claimTime
    ) public {
        vm.assume(receiver != address(0));
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        claimTime = bound(claimTime, start + cliff, type(uint128).max);
        total = bound(total, TOTAL, type(uint128).max);

        uint256 id = vest.create(receiver, start, cliff, duration, manager, restricted, protected, total);

        vm.warp(claimTime);

        vm.prank(receiver);
        vest.claim(id);
        uint256 accrued = vest.getAccrued(block.timestamp, start, start + duration, total);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.claimed, accrued);
    }

    function testAccruedWithTimeBeforeStart(uint256 time, uint256 start, uint256 end, uint256 total) public {
        start = bound(start, 1, type(uint256).max);
        time = bound(time, 0, start - 1);

        assertEq(vest.getAccrued(time, start, end, total), 0);
    }

    function testAccruedWithTimeAfterEnd(uint256 time, uint256 start, uint256 end, uint256 total) public {
        start = bound(start, 0, type(uint256).max - 1);
        end = bound(end, start + 1, type(uint256).max);
        time = bound(time, end, type(uint256).max);

        assertEq(vest.getAccrued(time, start, end, total), total);
    }

    function testAccrued(uint256 time, uint256 start, uint256 end, uint256 total) public {
        start = bound(start, 0, type(uint128).max - 1);
        end = bound(end, start + 1, type(uint128).max);
        time = bound(time, start + 1, end);
        total = bound(total, 0, type(uint128).max);

        uint256 expected = total * (time - start) / (end - start);

        assertEq(vest.getAccrued(time, start, end, total), expected);
    }

    function testUnclaimedBeforeCliff(uint256 time, uint256 start, uint256 cliff, uint256 duration, uint256 total)
        public
    {
        total = bound(total, 1, type(uint128).max);
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, 1, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        time = bound(time, 0, start + cliff - 1);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        vm.warp(time);

        uint256 unclaimed = vest.getUnclaimed(id);

        assertEq(unclaimed, 0);
    }

    function testUnclaimedAfterCliff(
        uint256 timeClaim,
        uint256 timeUnclaimed,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 total
    ) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, OFFSET, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        timeClaim = bound(timeClaim, start + cliff, type(uint96).max);
        timeUnclaimed = bound(timeUnclaimed, timeClaim + 1, type(uint128).max);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        vm.warp(timeClaim);

        vm.prank(alice);
        vest.claim(id);
        uint256 claimedBefore = vest.getVesting(id).claimed;

        vm.warp(timeUnclaimed);

        uint256 accrued = vest.getAccrued(block.timestamp, start, start + duration, total);
        uint256 expectedUnclaimed = accrued - claimedBefore;
        uint256 unclaimed = vest.getUnclaimed(id);

        assertApproxEqAbs(unclaimed, expectedUnclaimed, 1);
    }

    function testRevokeShouldRevertWhenCalledByNotOwner(address caller, uint256 id) public {
        vm.assume(caller != address(this));

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller);
        vest.revoke(id);
    }

    function testRevokeBeforeStart(uint256 end, uint256 start, uint256 cliff, uint256 duration, uint256 total) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, block.timestamp, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        end = bound(end, 0, start - 1);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        vest.revoke(id, end);

        end = end < block.timestamp ? block.timestamp : end;

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.start, end, "start");
        assertEq(vesting.end, end, "end");
        assertEq(vesting.total, 0, "total");
    }

    function testRevokeBeforeCliff(uint256 end, uint256 start, uint256 cliff, uint256 duration, uint256 total) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, block.timestamp, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, OFFSET, duration);
        end = bound(end, start, start + cliff - 1);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        vest.revoke(id, end);

        end = end < block.timestamp ? block.timestamp : end;

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.start, start, "start");
        assertEq(vesting.end, end, "end");
        assertEq(vesting.total, 0, "total");
    }

    function testRevokeAfterEnd(uint256 end, uint256 start, uint256 cliff, uint256 duration, uint256 total) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, block.timestamp, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration);
        end = bound(end, start + duration, type(uint256).max);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        Vest.Vesting memory vestingBefore = vest.getVesting(id);

        vest.revoke(id, end);

        end = end < block.timestamp ? block.timestamp : end;

        Vest.Vesting memory vestingAfter = vest.getVesting(id);

        assertEq(vestingAfter.start, vestingBefore.start, "start");
        assertEq(vestingAfter.end, vestingBefore.end, "end");
        assertEq(vestingAfter.total, vestingBefore.total, "total");
    }

    function testRevokeAfterCliffAndBeforeEnd(
        uint256 end,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 total
    ) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, block.timestamp, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration - 1);
        end = bound(end, start + cliff, start + duration - 1);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        Vest.Vesting memory vestingBefore = vest.getVesting(id);

        vest.revoke(id, end);

        end = end < block.timestamp ? block.timestamp : end;
        uint256 expectedTotal = vest.getAccrued(vestingBefore.end, start, end, total);

        Vest.Vesting memory vestingAfter = vest.getVesting(id);

        assertEq(vestingAfter.start, vestingBefore.start, "start");
        assertEq(vestingAfter.end, end, "end");
        assertEq(vestingAfter.total, expectedTotal, "total");
    }

    function testRevokeEndShouldAtLeastBlockTimestamp(
        uint256 end,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 total
    ) public {
        total = bound(total, TOTAL, type(uint128).max);
        start = bound(start, block.timestamp, block.timestamp + TWENTY_YEARS);
        duration = bound(duration, OFFSET, TWENTY_YEARS);
        cliff = bound(cliff, 0, duration - 1);
        end = bound(end, 0, start + duration - 1);

        uint256 id = vest.create(alice, start, cliff, duration, address(0), false, false, total);

        vest.revoke(id, end);

        Vest.Vesting memory vesting = vest.getVesting(id);

        assertEq(vesting.end, end < block.timestamp ? block.timestamp : end, "end");
    }

    function invariantDeadlines() public {
        Vest.Vesting memory vesting = vest.getVesting(0);
        assertLe(vesting.start, vesting.cliff);
        assertLe(vesting.start, vesting.end);
    }

    function invariantClaimed() public {
        Vest.Vesting memory vesting = vest.getVesting(0);
        assertLe(vesting.claimed, vesting.total);
    }

    function invariantUnclaimed() public {
        Vest.Vesting memory vesting = vest.getVesting(0);
        uint256 unclaimed = vest.getUnclaimed(0);
        assertLe(unclaimed, vesting.total);
    }

    function _createVest() internal returns (uint256 id) {
        id = vest.create(alice, START, 0, DURATION, address(0), false, false, TOTAL);
    }
}
