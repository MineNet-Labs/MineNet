// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title Roles
 * @author 0xEmmyb2
 * @notice MineNet participant roles: the 9 core roles plus PROCESSOR, CUSTOMS and ACCREDITOR.
 * @dev Contracts never check roles directly; they check {Actions}, which the registry maps to roles. The
 * platform admin (`DEFAULT_ADMIN_ROLE`) is separate: it onboards participants and pauses the system, and never
 * acts in the supply chain, edits lot history or decides disputes.
 */
library Roles {
    /**
     * @notice Mining company or cooperative that extracts minerals and registers lots.
     */
    bytes32 internal constant MINER = keccak256("MINER_ROLE");

    /**
     * @notice Refinery or smelter that processes lots and may buy them.
     */
    bytes32 internal constant REFINERY = keccak256("REFINERY_ROLE");

    /**
     * @notice Licensed carrier of mineral shipments.
     */
    bytes32 internal constant TRANSPORTER = keccak256("TRANSPORTER_ROLE");

    /**
     * @notice Trader or end buyer of mineral lots.
     */
    bytes32 internal constant BUYER = keccak256("BUYER_ROLE");

    /**
     * @notice Licensed (or bonded) warehouse that stores lots.
     */
    bytes32 internal constant WAREHOUSE = keccak256("WAREHOUSE_ROLE");

    /**
     * @notice Independent inspector that attests grade, weight and compliance.
     */
    bytes32 internal constant INSPECTOR = keccak256("INSPECTOR_ROLE");

    /**
     * @notice Auditor that reviews lots and supply-chain records and raises flags.
     */
    bytes32 internal constant AUDITOR = keccak256("AUDITOR_ROLE");

    /**
     * @notice Regulator from a licensing institution (RMB, RURA, RRA, BNR).
     */
    bytes32 internal constant REGULATOR = keccak256("REGULATOR_ROLE");

    /**
     * @notice Oracle node that posts signed readings, reports and reference rates.
     */
    bytes32 internal constant ORACLE = keccak256("ORACLE_ROLE");

    /**
     * @notice Primary processor operating near the mine.
     */
    bytes32 internal constant PROCESSOR = keccak256("PROCESSOR_ROLE");

    /**
     * @notice Licensed customs clearing agent (RRA).
     */
    bytes32 internal constant CUSTOMS = keccak256("CUSTOMS_ROLE");

    /**
     * @notice Accreditation or standards body that accredits auditors for a scheme: the ICGLR Audit Committee (ICGLR
     * third-party audits, reviewed by the Independent Mineral Chain Auditor), the Responsible Minerals Initiative
     * (RMAP smelter and refiner audits), or ICPAR (licensed financial auditors).
     */
    bytes32 internal constant ACCREDITOR = keccak256("ACCREDITOR_ROLE");
}
