// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Roles} from "src/access/libraries/Roles.sol";

/**
 * @title Actions
 * @author 0xEmmyb2
 * @notice Permission actions: what a participant may DO, as opposed to what it IS (a role).
 * @dev Contracts check actions, never roles: `registry.isAuthorized(account, Actions.SELL_LOT)`. The admin
 * decides which roles may perform each action in {MineNetRegistry-setActionRoles}, so changing who may do what
 * (e.g. letting processors buy lots, or adding a new role) needs no redeployment.
 */
library Actions {
    /**
     * @notice Mint a lot passport from one of the organisation's mine sites.
     */
    bytes32 internal constant REGISTER_LOT = keccak256("REGISTER_LOT");

    /**
     * @notice Attest inspections and grades, and inspect site safety and reserves.
     */
    bytes32 internal constant INSPECT_LOT = keccak256("INSPECT_LOT");

    /**
     * @notice Receive ownership of a lot.
     */
    bytes32 internal constant OWN_LOT = keccak256("OWN_LOT");

    /**
     * @notice List lots for sale and fill buy requests.
     */
    bytes32 internal constant SELL_LOT = keccak256("SELL_LOT");

    /**
     * @notice Buy listings and post buy requests.
     */
    bytes32 internal constant BUY_LOT = keccak256("BUY_LOT");

    /**
     * @notice Receive physical custody of a lot.
     */
    bytes32 internal constant HOLD_CUSTODY = keccak256("HOLD_CUSTODY");

    /**
     * @notice Carry shipments.
     */
    bytes32 internal constant CARRY = keccak256("CARRY");

    /**
     * @notice Be the consignee of a shipment.
     */
    bytes32 internal constant RECEIVE_SHIPMENT = keccak256("RECEIVE_SHIPMENT");

    /**
     * @notice Transform lots (split, merge, concentrate, refine).
     */
    bytes32 internal constant PROCESS_LOTS = keccak256("PROCESS_LOTS");

    /**
     * @notice Record warehouse check-in and check-out weights.
     */
    bytes32 internal constant OPERATE_WAREHOUSE = keccak256("OPERATE_WAREHOUSE");

    /**
     * @notice File customs declarations and record border exits.
     */
    bytes32 internal constant FILE_CUSTOMS = keccak256("FILE_CUSTOMS");

    /**
     * @notice Post oracle readings, reports and FX rates.
     */
    bytes32 internal constant REPORT_READING = keccak256("REPORT_READING");

    /**
     * @notice Perform audits and raise flags.
     */
    bytes32 internal constant AUDIT = keccak256("AUDIT");

    /**
     * @notice Freeze lots, raise and resolve flags, suspend participants, place holds and manage licences.
     */
    bytes32 internal constant REGULATE = keccak256("REGULATE");

    /**
     * @notice Manage workers, attendance and payroll.
     */
    bytes32 internal constant MANAGE_WORKFORCE = keccak256("MANAGE_WORKFORCE");

    /**
     * @notice Scan lot QR tags (with OCR comparison) along the chain.
     */
    bytes32 internal constant SCAN_TAG = keccak256("SCAN_TAG");

    /**
     * @notice Propose, negotiate, sign and close business-to-business agreements ({B2B}).
     * @dev Every business role by default; regulators and oracle nodes stay neutral and cannot contract.
     */
    bytes32 internal constant ENTER_AGREEMENT = keccak256("ENTER_AGREEMENT");

    /**
     * @notice Accredit auditors, review audit reports and publish their summaries ({AuditRegistry}).
     */
    bytes32 internal constant ACCREDIT = keccak256("ACCREDIT");

    /**
     * @notice The default action-to-roles table, installed by {MineNetRegistry} at deployment.
     * @return actions Every action, in a fixed order.
     * @return roles For each entry of `actions`, the roles allowed to perform it.
     */
    function defaults() internal pure returns (bytes32[] memory actions, bytes32[][] memory roles) {
        actions = new bytes32[](18);
        roles = new bytes32[][](18);

        actions[0] = REGISTER_LOT;
        roles[0] = _one(Roles.MINER);
        actions[1] = INSPECT_LOT;
        roles[1] = _one(Roles.INSPECTOR);
        actions[2] = OWN_LOT;
        roles[2] = _two(Roles.BUYER, Roles.REFINERY);
        actions[3] = SELL_LOT;
        roles[3] = _three(Roles.MINER, Roles.BUYER, Roles.REFINERY);
        actions[4] = BUY_LOT;
        roles[4] = _two(Roles.BUYER, Roles.REFINERY);

        actions[5] = HOLD_CUSTODY;
        roles[5] = new bytes32[](5);
        roles[5][0] = Roles.TRANSPORTER;
        roles[5][1] = Roles.WAREHOUSE;
        roles[5][2] = Roles.PROCESSOR;
        roles[5][3] = Roles.REFINERY;
        roles[5][4] = Roles.BUYER;

        actions[6] = CARRY;
        roles[6] = _one(Roles.TRANSPORTER);

        actions[7] = RECEIVE_SHIPMENT;
        roles[7] = new bytes32[](4);
        roles[7][0] = Roles.WAREHOUSE;
        roles[7][1] = Roles.PROCESSOR;
        roles[7][2] = Roles.REFINERY;
        roles[7][3] = Roles.BUYER;

        actions[8] = PROCESS_LOTS;
        roles[8] = _two(Roles.PROCESSOR, Roles.REFINERY);
        actions[9] = OPERATE_WAREHOUSE;
        roles[9] = _one(Roles.WAREHOUSE);
        actions[10] = FILE_CUSTOMS;
        roles[10] = _one(Roles.CUSTOMS);
        actions[11] = REPORT_READING;
        roles[11] = _one(Roles.ORACLE);
        actions[12] = AUDIT;
        roles[12] = _one(Roles.AUDITOR);
        actions[13] = REGULATE;
        roles[13] = _one(Roles.REGULATOR);
        actions[14] = MANAGE_WORKFORCE;
        roles[14] = _three(Roles.MINER, Roles.PROCESSOR, Roles.REFINERY);

        // everyone who handles or checks a lot along the chain scans its tag
        actions[15] = SCAN_TAG;
        roles[15] = new bytes32[](10);
        roles[15][0] = Roles.MINER;
        roles[15][1] = Roles.TRANSPORTER;
        roles[15][2] = Roles.WAREHOUSE;
        roles[15][3] = Roles.PROCESSOR;
        roles[15][4] = Roles.REFINERY;
        roles[15][5] = Roles.BUYER;
        roles[15][6] = Roles.INSPECTOR;
        roles[15][7] = Roles.CUSTOMS;
        roles[15][8] = Roles.ORACLE;
        roles[15][9] = Roles.REGULATOR;

        // every business can contract with another business; regulators and oracles stay neutral
        actions[16] = ENTER_AGREEMENT;
        roles[16] = new bytes32[](9);
        roles[16][0] = Roles.MINER;
        roles[16][1] = Roles.REFINERY;
        roles[16][2] = Roles.TRANSPORTER;
        roles[16][3] = Roles.BUYER;
        roles[16][4] = Roles.WAREHOUSE;
        roles[16][5] = Roles.PROCESSOR;
        roles[16][6] = Roles.INSPECTOR;
        roles[16][7] = Roles.AUDITOR;
        roles[16][8] = Roles.CUSTOMS;

        // accreditation bodies (ICGLR Audit Committee, RMI, ICPAR) accredit auditors and review their reports
        actions[17] = ACCREDIT;
        roles[17] = _one(Roles.ACCREDITOR);
    }

    /**
     * @dev Builds a one-element role list.
     * @param a The role.
     * @return r `[a]`.
     */
    function _one(bytes32 a) private pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    /**
     * @dev Builds a two-element role list.
     * @param a First role.
     * @param b Second role.
     * @return r `[a, b]`.
     */
    function _two(bytes32 a, bytes32 b) private pure returns (bytes32[] memory r) {
        r = new bytes32[](2);
        r[0] = a;
        r[1] = b;
    }

    /**
     * @dev Builds a three-element role list.
     * @param a First role.
     * @param b Second role.
     * @param c Third role.
     * @return r `[a, b, c]`.
     */
    function _three(bytes32 a, bytes32 b, bytes32 c) private pure returns (bytes32[] memory r) {
        r = new bytes32[](3);
        r[0] = a;
        r[1] = b;
        r[2] = c;
    }
}
