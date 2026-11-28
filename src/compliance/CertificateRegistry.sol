// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICertificateRegistry} from "src/compliance/interfaces/ICertificateRegistry.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {CertificateLib} from "src/compliance/libraries/CertificateLib.sol";

/**
 * @title CertificateRegistry
 * @author 0xEmmyb2
 * @notice Compliance certificates per lot, such as an export permit, an ICGLR regional certificate, a
 * conflict-free / OECD due-diligence attestation, or an assay certificate.
 * @dev Each certificate type can only be issued by one configured role, for example `EXPORT_PERMIT -> REGULATOR`,
 * `ASSAY -> INSPECTOR`, `CONFLICT_FREE -> AUDITOR`. Certificates expire and can be revoked. Other contracts
 * ({EscrowManager}, {SupplyChain}) call {hasValidCertificate} to gate trades and exports. Only a document hash is
 * stored.
 */
contract CertificateRegistry is ICertificateRegistry {
    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport the certificates refer to.
     */
    ILotPassport public immutable passport;

    /**
     * @dev Next certificate id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextCertId = 1;

    /**
     * @dev Certificate id => certificate.
     */
    mapping(uint256 certId => CertificateLib.Certificate) private _certs;

    /**
     * @notice Role allowed to issue each certificate type (zero = type disabled).
     */
    mapping(bytes32 certType => bytes32 issuerRole) public issuerRoleOf;

    /**
     * @notice A lot's current certificate of each type (0 = none).
     */
    mapping(uint256 tokenId => mapping(bytes32 certType => uint256 certId)) public latestCertificate;

    /**
     * @notice The contract allowed to link split lots to their parent ({SupplyChain}; zero = none).
     */
    address public splitter;

    /**
     * @notice The lot a split lot was cut from (zero = not a split lot). A split lot without its own certificate
     * of a type is covered by its parent's.
     */
    mapping(uint256 tokenId => uint256 parentId) public splitParentOf;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_) {
        registry = registry_;
        passport = passport_;
    }

    /**
     * @notice Sets the contract allowed to link split lots to their parent.
     * @dev Only a {MineNetRegistry} admin.
     * @param splitter_ The contract ({SupplyChain}), or zero.
     * @custom:emits SplitterSet
     */
    function setSplitter(address splitter_) external {
        if (!registry.isAdmin(msg.sender)) revert CertificateLib.CertificateRegistry__NotRegistryAdmin(msg.sender);
        splitter = splitter_;
        emit CertificateLib.SplitterSet(splitter_);
    }

    /**
     * @inheritdoc ICertificateRegistry
     * @custom:emits SplitLinked
     */
    function linkSplit(uint256 childId, uint256 parentId) external {
        if (msg.sender != splitter || msg.sender == address(0)) {
            revert CertificateLib.CertificateRegistry__NotSplitter(msg.sender);
        }
        splitParentOf[childId] = parentId;
        emit CertificateLib.SplitLinked(childId, parentId);
    }

    /**
     * @notice Chooses which role issues `certType`.
     * @dev Only a {MineNetRegistry} admin. Passing `bytes32(0)` disables the type; certificates already issued stay
     * valid until they expire or are revoked.
     * @param certType Certificate type.
     * @param issuerRole Participant role allowed to issue it, or zero to disable the type.
     * @custom:emits CertificateTypeConfigured
     */
    function configureCertType(bytes32 certType, bytes32 issuerRole) external {
        if (!registry.isAdmin(msg.sender)) {
            revert CertificateLib.CertificateRegistry__NotRegistryAdmin(msg.sender);
        }
        if (issuerRole != bytes32(0) && !registry.isParticipantRole(issuerRole)) {
            revert CertificateLib.CertificateRegistry__InvalidIssuerRole(issuerRole);
        }
        issuerRoleOf[certType] = issuerRole;
        emit CertificateLib.CertificateTypeConfigured(certType, issuerRole);
    }

    /**
     * @notice Issues a certificate for a lot. It becomes the lot's current certificate of that type.
     * @dev Only an active holder of the type's issuer role.
     * @param tokenId Lot.
     * @param certType Certificate type.
     * @param expiresAt Expiry (unix seconds), or 0 for none; must be in the future.
     * @param docHash Hash of the certificate document.
     * @return certId New certificate id.
     * @custom:emits CertificateIssued
     */
    function issue(uint256 tokenId, bytes32 certType, uint64 expiresAt, bytes32 docHash)
        external
        returns (uint256 certId)
    {
        bytes32 role = issuerRoleOf[certType];
        if (role == bytes32(0)) revert CertificateLib.CertificateRegistry__UnknownCertType(certType);
        if (!registry.isActive(msg.sender, role)) {
            revert CertificateLib.CertificateRegistry__Unauthorized(msg.sender, role);
        }
        if (expiresAt != 0 && expiresAt <= block.timestamp) {
            revert CertificateLib.CertificateRegistry__InvalidExpiry(expiresAt);
        }
        passport.getLot(tokenId); // reverts with UnknownLot if the lot does not exist

        certId = _nextCertId++;
        _certs[certId] = CertificateLib.Certificate({
            tokenId: tokenId,
            certType: certType,
            issuer: msg.sender,
            issuedAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            revoked: false,
            docHash: docHash
        });
        latestCertificate[tokenId][certType] = certId;
        emit CertificateLib.CertificateIssued(certId, tokenId, certType, msg.sender, expiresAt, docHash);
    }

    /**
     * @notice Revokes a certificate.
     * @dev Only its issuer or an active regulator.
     * @param certId Certificate id.
     * @param reasonHash Hash of the revocation decision.
     * @custom:emits CertificateRevoked
     */
    function revoke(uint256 certId, bytes32 reasonHash) external {
        CertificateLib.Certificate storage c = _certs[certId];
        if (c.issuer == address(0)) revert CertificateLib.CertificateRegistry__UnknownCertificate(certId);
        if (c.revoked) revert CertificateLib.CertificateRegistry__AlreadyRevoked(certId);
        if (msg.sender != c.issuer && !registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert CertificateLib.CertificateRegistry__NotIssuerOrRegulator(msg.sender);
        }
        c.revoked = true;
        emit CertificateLib.CertificateRevoked(certId, c.tokenId, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a certificate.
     * @param certId Certificate id.
     * @return The certificate (all fields zero if unknown).
     */
    function getCertificate(uint256 certId) external view returns (CertificateLib.Certificate memory) {
        return _certs[certId];
    }

    /**
     * @notice Whether a certificate exists, is not revoked and has not expired.
     * @param certId Certificate id.
     * @return True if valid.
     */
    function isValid(uint256 certId) public view returns (bool) {
        return CertificateLib.isValid(_certs[certId]);
    }

    /**
     * @notice Whether a lot's current certificate of `certType` is valid. A split lot without its own
     * certificate of that type is covered by the one of the lot it was cut from.
     * @param tokenId Lot.
     * @param certType Certificate type.
     * @return True if unrevoked and unexpired.
     */
    function hasValidCertificate(uint256 tokenId, bytes32 certType) public view returns (bool) {
        uint256 certId = latestCertificate[tokenId][certType];
        while (certId == 0) {
            tokenId = splitParentOf[tokenId];
            if (tokenId == 0) return false;
            certId = latestCertificate[tokenId][certType];
        }
        return isValid(certId);
    }

    /**
     * @notice Whether a lot holds a valid current certificate of every listed type.
     * @param tokenId Lot.
     * @param certTypes Certificate types.
     * @return True if every type is covered (also true for an empty list).
     */
    function hasValidCertificates(uint256 tokenId, bytes32[] memory certTypes) external view returns (bool) {
        for (uint256 i; i < certTypes.length; ++i) {
            if (!hasValidCertificate(tokenId, certTypes[i])) return false;
        }
        return true;
    }
}
