// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title CertificateLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {CertificateRegistry}.
 */
library CertificateLib {
    /**
     * @notice A certificate issued for a lot.
     * @param tokenId Lot passport the certificate is about.
     * @param certType Certificate type (e.g. export permit, conflict-free).
     * @param issuer Account that issued it.
     * @param issuedAt Block timestamp of issuance.
     * @param expiresAt Expiry (unix seconds); 0 = never expires.
     * @param revoked True once revoked.
     * @param docHash Hash of the certificate document held off-chain.
     */
    struct Certificate {
        uint256 tokenId;
        bytes32 certType;
        address issuer;
        uint64 issuedAt;
        uint64 expiresAt;
        bool revoked;
        bytes32 docHash;
    }

    /**
     * @notice Emitted when the admin configures which role issues a certificate type.
     * @param certType Certificate type.
     * @param issuerRole Role allowed to issue it.
     */
    event CertificateTypeConfigured(bytes32 indexed certType, bytes32 indexed issuerRole);

    /**
     * @notice Emitted when the admin sets the split linker.
     * @param splitter The contract (zero = none).
     */
    event SplitterSet(address splitter);

    /**
     * @notice Emitted when a split lot is linked to the lot it was cut from.
     * @param childId Split lot.
     * @param parentId Parent lot.
     */
    event SplitLinked(uint256 indexed childId, uint256 indexed parentId);

    /**
     * @notice Emitted when a certificate is issued.
     * @param certId New certificate id.
     * @param tokenId Lot passport it is about.
     * @param certType Certificate type.
     * @param issuer Issuing account.
     * @param expiresAt Expiry (0 = never).
     * @param docHash Hash of the certificate document.
     */
    event CertificateIssued(
        uint256 indexed certId,
        uint256 indexed tokenId,
        bytes32 indexed certType,
        address issuer,
        uint64 expiresAt,
        bytes32 docHash
    );

    /**
     * @notice Emitted when a certificate is revoked.
     * @param certId Revoked certificate.
     * @param tokenId Lot passport it is about.
     * @param by Issuer or regulator that revoked it.
     * @param reasonHash Hash of the revocation decision.
     */
    event CertificateRevoked(uint256 indexed certId, uint256 indexed tokenId, address indexed by, bytes32 reasonHash);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error CertificateRegistry__NotRegistryAdmin(address account);

    /**
     * @notice The caller is not the split linker ({SupplyChain}).
     * @param account The caller.
     */
    error CertificateRegistry__NotSplitter(address account);

    /**
     * @notice `certType` has not been configured.
     * @param certType The certificate type.
     */
    error CertificateRegistry__UnknownCertType(bytes32 certType);

    /**
     * @notice `role` cannot issue certificates.
     * @param role The role.
     */
    error CertificateRegistry__InvalidIssuerRole(bytes32 role);

    /**
     * @notice `account` does not hold `role`, the issuer role of the certificate type.
     * @param account The account.
     * @param role Required issuer role.
     */
    error CertificateRegistry__Unauthorized(address account, bytes32 role);

    /**
     * @notice `expiresAt` is in the past.
     * @param expiresAt Supplied expiry.
     */
    error CertificateRegistry__InvalidExpiry(uint64 expiresAt);

    /**
     * @notice Certificate `certId` does not exist.
     * @param certId The certificate id.
     */
    error CertificateRegistry__UnknownCertificate(uint256 certId);

    /**
     * @notice Certificate `certId` is already revoked.
     * @param certId The certificate id.
     */
    error CertificateRegistry__AlreadyRevoked(uint256 certId);

    /**
     * @notice `account` is neither the certificate's issuer nor a regulator.
     * @param account The account.
     */
    error CertificateRegistry__NotIssuerOrRegulator(address account);

    /**
     * @notice Whether a certificate exists, is not revoked and has not expired.
     * @param c The certificate.
     * @return True if the certificate is currently valid.
     */
    function isValid(Certificate storage c) internal view returns (bool) {
        return c.issuer != address(0) && !c.revoked && (c.expiresAt == 0 || c.expiresAt > block.timestamp);
    }
}
