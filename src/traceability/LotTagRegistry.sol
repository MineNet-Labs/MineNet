// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ILotTagRegistry} from "src/traceability/interfaces/ILotTagRegistry.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {TraceLib} from "src/traceability/libraries/TraceLib.sol";

/**
 * @title LotTagRegistry
 * @author 0xEmmyb2
 * @notice Physical QR (or other digital) tags on mineral lots, and the scans made along the chain, to make
 * smuggling and lot swapping visible.
 * @dev Each lot carries one active tag. Only the hash of the tag's payload (a random serial, never reused) is
 * stored. The lot's owner or custodian binds the first tag. A damaged or lost tag is replaced only by an
 * independent inspector or a regulator, and the old tag becomes Void forever.
 *
 * Scans: whoever handles or checks the lot (`SCAN_TAG`) scans the QR code, and the scanning app reads the printed
 * label and documents with OCR and compares them with the lot record. The scan is recorded with the OCR output's
 * hash and the location:
 * - `Match`: tag active and OCR consistent with the lot.
 * - `OcrMismatch`: tag active but the label / documents do not match the lot; the lot is flagged.
 * - `VoidTag`: a replaced tag is still on material (possible clone); the lot is flagged.
 * - `UnknownTag`: no lot has this tag (untracked, possibly smuggled material); reported.
 * A flag freezes the lot on the passport until a regulator resolves it. Buyers and the public can check any tag
 * with {verifyTag}.
 *
 * Must be enabled as a passport module (`passport.setModule`) so it can raise flags.
 */
contract LotTagRegistry is ILotTagRegistry {
    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport the tags refer to.
     */
    ILotPassport public immutable passport;

    /**
     * @dev Tag hash => tag record.
     */
    mapping(bytes32 tagHash => TraceLib.Tag) private _tags;

    /**
     * @notice A lot's current active tag (zero if none).
     */
    mapping(uint256 tokenId => bytes32 tagHash) public tagOf;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_) {
        registry = registry_;
        passport = passport_;
    }

    /**
     * @notice Attaches the first tag to a lot.
     * @dev Only the lot's owner or custodian, and only while the lot has no tag.
     * @param tokenId Lot.
     * @param tagHash Hash of the tag's payload; non-zero and never used before.
     * @custom:emits TagBound
     */
    function bindTag(uint256 tokenId, bytes32 tagHash) external {
        if (msg.sender != passport.ownerOf(tokenId) && msg.sender != passport.custodianOf(tokenId)) {
            revert TraceLib.LotTagRegistry__NotOwnerOrCustodian(tokenId, msg.sender);
        }
        bytes32 current = tagOf[tokenId];
        if (current != bytes32(0)) revert TraceLib.LotTagRegistry__LotHasTag(tokenId, current);
        _bind(tokenId, tagHash);
    }

    /**
     * @notice Replaces a lot's damaged or lost tag. The old tag is voided forever.
     * @dev Only an inspector or regulator who is neither the lot's owner nor its custodian.
     * @param tokenId Lot.
     * @param newTagHash Hash of the new tag's payload; non-zero and never used before.
     * @param reasonHash Hash of the reason for the replacement.
     * @custom:emits TagVoided
     * @custom:emits TagBound
     */
    function replaceTag(uint256 tokenId, bytes32 newTagHash, bytes32 reasonHash) external {
        if (
            !registry.isAuthorized(msg.sender, Actions.INSPECT_LOT)
                && !registry.isAuthorized(msg.sender, Actions.REGULATE)
        ) revert TraceLib.LotTagRegistry__Unauthorized(msg.sender);
        if (msg.sender == passport.ownerOf(tokenId) || msg.sender == passport.custodianOf(tokenId)) {
            revert TraceLib.LotTagRegistry__Unauthorized(msg.sender);
        }
        bytes32 old = tagOf[tokenId];
        if (old == bytes32(0)) revert TraceLib.LotTagRegistry__NoActiveTag(tokenId);
        _tags[old].status = TraceLib.TagStatus.Void;
        emit TraceLib.TagVoided(tokenId, old, msg.sender, reasonHash);
        _bind(tokenId, newTagHash);
    }

    /**
     * @notice Records a tag scan; flags the lot on an OCR mismatch or a void tag.
     * @dev Only accounts with `SCAN_TAG`.
     * @param tagHash Hash of the scanned tag's payload.
     * @param ocrHash Hash of the OCR output, kept as evidence.
     * @param ocrMatch The scanning app's comparison of the OCR read with the lot record.
     * @param locationHash Hash of the scan location.
     * @return result Outcome of the scan.
     * @custom:emits TagScanned
     */
    function recordScan(bytes32 tagHash, bytes32 ocrHash, bool ocrMatch, bytes32 locationHash)
        external
        returns (TraceLib.ScanResult result)
    {
        if (!registry.isAuthorized(msg.sender, Actions.SCAN_TAG)) {
            revert TraceLib.LotTagRegistry__Unauthorized(msg.sender);
        }
        TraceLib.Tag storage t = _tags[tagHash];
        uint256 tokenId = t.tokenId;

        if (t.status == TraceLib.TagStatus.None) {
            result = TraceLib.ScanResult.UnknownTag;
        } else {
            t.scans += 1;
            if (t.status == TraceLib.TagStatus.Void) result = TraceLib.ScanResult.VoidTag;
            else if (!ocrMatch) result = TraceLib.ScanResult.OcrMismatch;
            else result = TraceLib.ScanResult.Match;
        }
        emit TraceLib.TagScanned(tagHash, tokenId, msg.sender, result, ocrHash, locationHash);

        if (result == TraceLib.ScanResult.VoidTag || result == TraceLib.ScanResult.OcrMismatch) {
            passport.moduleFlag(tokenId, msg.sender, keccak256(abi.encode("TAG_SCAN", result, tagHash, ocrHash)));
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a tag record.
     * @param tagHash Hash of the tag's payload.
     * @return The tag record (status `None` if unknown).
     */
    function getTag(bytes32 tagHash) external view returns (TraceLib.Tag memory) {
        return _tags[tagHash];
    }

    /**
     * @notice What a scanned tag says about its lot.
     * @param tagHash Hash of the tag's payload.
     * @return tokenId Lot the tag belongs to (0 for an unknown tag).
     * @return active Whether the tag is the lot's current one.
     * @return frozen Whether the lot is frozen.
     */
    function verifyTag(bytes32 tagHash) external view returns (uint256 tokenId, bool active, bool frozen) {
        TraceLib.Tag storage t = _tags[tagHash];
        tokenId = t.tokenId;
        active = t.status == TraceLib.TagStatus.Active;
        frozen = tokenId != 0 && passport.isFrozen(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Binds a fresh tag to an existing lot as its current tag.
     * @param tokenId Lot.
     * @param tagHash Hash of the tag's payload.
     */
    function _bind(uint256 tokenId, bytes32 tagHash) private {
        if (tagHash == bytes32(0)) revert TraceLib.LotTagRegistry__InvalidTag();
        if (_tags[tagHash].status != TraceLib.TagStatus.None) revert TraceLib.LotTagRegistry__TagUsed(tagHash);
        passport.getLot(tokenId); // reverts for an unknown lot
        _tags[tagHash] = TraceLib.Tag({
            tokenId: tokenId, status: TraceLib.TagStatus.Active, boundAt: uint64(block.timestamp), scans: 0
        });
        tagOf[tokenId] = tagHash;
        emit TraceLib.TagBound(tokenId, tagHash, msg.sender);
    }
}
