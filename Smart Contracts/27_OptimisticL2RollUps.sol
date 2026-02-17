// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ✅ Advanced Optimistic Rollup Simulation (Production-style)
 * Uses OpenZeppelin direct implementations:
 *  - Ownable
 *  - Pausable
 *  - ReentrancyGuard
 *  - SafeERC20
 *  - MerkleProof
 *
 * Flow:
 * 1) Users deposit ETH / ERC20 into this L1 escrow.
 * 2) Sequencer submits batches (txDataHash + newStateRoot + withdrawalRoot).
 * 3) Anyone can challenge within challengeWindow (optimistic model).
 * 4) Challenge resolved using external FraudProofVerifier.
 * 5) After finalization, users claim withdrawals via Merkle proof.
 *
 * NOTE: This is a simulation; L2 txs are not executed on-chain.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";          // OZ v4.x
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";   // OZ v4.x
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFraudProofVerifier {
    function verifiesFraud(
        bytes calldata proof,
        bytes32 txDataHash,
        bytes32 prevStateRoot,
        bytes32 newStateRoot
    ) external view returns (bool);
}

contract OptimisticRollupSimulation is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error NotSequencer();
    error BadBatch();
    error ChallengePeriodActive();
    error ChallengePeriodOver();
    error AlreadyChallenged();
    error NotChallenger();
    error BatchNotFound();
    error BatchAlreadyFinalized();
    error BatchNotFinalized();
    error InvalidProof();
    error WithdrawalAlreadyClaimed();
    error TransferFailed();
    error ZeroAmount();

    // ---------- Roles ----------
    address public sequencer;
    IFraudProofVerifier public fraudVerifier;

    // ---------- Economic Security ----------
    uint256 public sequencerBond;
    uint256 public challengerBond;
    uint256 public challengeWindow;

    // ETH bonds
    mapping(address => uint256) public bonds;

    // ---------- Batch State ----------
    struct Batch {
        bytes32 prevStateRoot;
        bytes32 newStateRoot;
        bytes32 txDataHash;
        bytes32 withdrawalRoot;
        uint64  submittedAt;
        bool    challenged;
        bool    finalized;
        address challenger;
    }

    uint256 public latestBatchId;
    mapping(uint256 => Batch) public batches;

    bytes32 public currentStateRoot;

    // ---------- Deposits ----------
    uint256 public depositNonce;
    event DepositETH(address indexed user, uint256 amount, uint256 indexed nonce);
    event DepositERC20(address indexed user, address indexed token, uint256 amount, uint256 indexed nonce);

    // ---------- Batches / Disputes ----------
    event SequencerUpdated(address indexed oldSequencer, address indexed newSequencer);
    event FraudVerifierUpdated(address indexed verifier);
    event ParamsUpdated(uint256 challengeWindow, uint256 sequencerBond, uint256 challengerBond);

    event BatchSubmitted(
        uint256 indexed batchId,
        bytes32 indexed prevStateRoot,
        bytes32 indexed newStateRoot,
        bytes32 txDataHash,
        bytes32 withdrawalRoot
    );

    event BatchChallenged(uint256 indexed batchId, address indexed challenger);
    event ChallengeResolved(uint256 indexed batchId, bool fraudProven);

    event BatchFinalized(uint256 indexed batchId, bytes32 indexed newStateRoot);

    // ---------- Withdrawals ----------
    mapping(uint256 => mapping(bytes32 => bool)) public withdrawalClaimed;
    event WithdrawalClaimed(
        uint256 indexed batchId,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 nonce
    );

    // ---------- Bonding ----------
    event Bonded(address indexed who, uint256 amount);
    event Unbonded(address indexed who, uint256 amount);

    // ---------- Constructor ----------
    constructor(
        address initialSequencer,
        address initialFraudVerifier,
        uint256 _challengeWindow,
        uint256 _sequencerBond,
        uint256 _challengerBond,
        bytes32 genesisStateRoot
    ) Ownable(msg.sender) {
        require(initialSequencer != address(0), "ZERO_SEQUENCER");

        sequencer = initialSequencer;
        fraudVerifier = IFraudProofVerifier(initialFraudVerifier);

        challengeWindow = _challengeWindow;
        sequencerBond = _sequencerBond;
        challengerBond = _challengerBond;

        currentStateRoot = genesisStateRoot;
    }

    // ---------- Admin Controls ----------
    function setSequencer(address newSequencer) external onlyOwner {
        require(newSequencer != address(0), "ZERO_ADDR");
        emit SequencerUpdated(sequencer, newSequencer);
        sequencer = newSequencer;
    }

    function setFraudVerifier(address verifier) external onlyOwner {
        fraudVerifier = IFraudProofVerifier(verifier);
        emit FraudVerifierUpdated(verifier);
    }

    function setParams(uint256 _challengeWindow, uint256 _sequencerBond, uint256 _challengerBond) external onlyOwner {
        challengeWindow = _challengeWindow;
        sequencerBond = _sequencerBond;
        challengerBond = _challengerBond;
        emit ParamsUpdated(_challengeWindow, _sequencerBond, _challengerBond);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---------- Bonding ----------
    function bond() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        bonds[msg.sender] += msg.value;
        emit Bonded(msg.sender, msg.value);
    }

    function unbond(uint256 amount) external whenNotPaused nonReentrant {
        require(bonds[msg.sender] >= amount, "INSUFFICIENT_BOND");
        bonds[msg.sender] -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Unbonded(msg.sender, amount);
    }

    // ---------- Deposits ----------
    function depositETH() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        uint256 n = ++depositNonce;
        emit DepositETH(msg.sender, msg.value, n);
    }

    function depositERC20(address token, uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 n = ++depositNonce;
        emit DepositERC20(msg.sender, token, amount, n);
    }

    // ---------- Batch Submission ----------
    modifier onlySequencer() {
        if (msg.sender != sequencer) revert NotSequencer();
        _;
    }

    function submitBatch(
        bytes32 newStateRoot,
        bytes32 txDataHash,
        bytes32 withdrawalRoot
    ) external whenNotPaused onlySequencer {
        require(bonds[msg.sender] >= sequencerBond, "SEQUENCER_BOND_LOW");
        if (newStateRoot == bytes32(0) || txDataHash == bytes32(0)) revert BadBatch();

        uint256 batchId = ++latestBatchId;
        Batch storage b = batches[batchId];

        b.prevStateRoot = currentStateRoot;
        b.newStateRoot = newStateRoot;
        b.txDataHash = txDataHash;
        b.withdrawalRoot = withdrawalRoot;
        b.submittedAt = uint64(block.timestamp);

        emit BatchSubmitted(batchId, b.prevStateRoot, b.newStateRoot, txDataHash, withdrawalRoot);

        // convenience pointer (NOT finality)
        currentStateRoot = newStateRoot;
    }

    // ---------- Challenge ----------
    function challengeBatch(uint256 batchId) external whenNotPaused {
        Batch storage b = batches[batchId];
        if (b.submittedAt == 0) revert BatchNotFound();
        if (b.finalized) revert BatchAlreadyFinalized();
        if (b.challenged) revert AlreadyChallenged();

        if (block.timestamp > uint256(b.submittedAt) + challengeWindow) revert ChallengePeriodOver();
        require(bonds[msg.sender] >= challengerBond, "CHALLENGER_BOND_LOW");

        b.challenged = true;
        b.challenger = msg.sender;

        emit BatchChallenged(batchId, msg.sender);
    }

    function resolveChallenge(uint256 batchId, bytes calldata proof) external whenNotPaused {
        Batch storage b = batches[batchId];
        if (b.submittedAt == 0) revert BatchNotFound();
        if (!b.challenged) revert NotChallenger();
        if (b.finalized) revert BatchAlreadyFinalized();

        // Only challenger or owner resolves (simulation choice)
        if (msg.sender != b.challenger && msg.sender != owner()) revert NotChallenger();

        if (address(fraudVerifier) == address(0)) revert InvalidProof();

        bool fraudProven = fraudVerifier.verifiesFraud(proof, b.txDataHash, b.prevStateRoot, b.newStateRoot);

        if (fraudProven) {
            // Slash sequencer and reward challenger (simple model)
            uint256 slashAmount = sequencerBond / 2;

            uint256 seqBond = bonds[sequencer];
            uint256 actualSlash = slashAmount > seqBond ? seqBond : slashAmount;

            if (actualSlash > 0) {
                bonds[sequencer] = seqBond - actualSlash;
                bonds[b.challenger] += actualSlash;
            }
            // Real rollup: handle state reversion + reorgs
        } else {
            // Small penalty for spam challenges (optional)
            uint256 penalty = challengerBond / 10;
            uint256 cBond = bonds[b.challenger];
            if (penalty > 0 && cBond >= penalty) {
                bonds[b.challenger] = cBond - penalty;
            }
        }

        b.challenged = false;

        emit ChallengeResolved(batchId, fraudProven);
    }

    // ---------- Finalization ----------
    function finalizeBatch(uint256 batchId) external whenNotPaused {
        Batch storage b = batches[batchId];
        if (b.submittedAt == 0) revert BatchNotFound();
        if (b.finalized) revert BatchAlreadyFinalized();

        if (block.timestamp <= uint256(b.submittedAt) + challengeWindow) revert ChallengePeriodActive();
        if (b.challenged) revert AlreadyChallenged();

        b.finalized = true;
        emit BatchFinalized(batchId, b.newStateRoot);
    }

    // ---------- Withdrawals ----------
    /**
     * Leaf format (must match your off-chain Merkle tree):
     * leaf = keccak256(abi.encodePacked(user, token, amount, nonce))
     */
    function claimWithdrawal(
        uint256 batchId,
        address token,       // address(0) => ETH
        uint256 amount,
        uint256 nonce,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        Batch storage b = batches[batchId];
        if (b.submittedAt == 0) revert BatchNotFound();
        if (!b.finalized) revert BatchNotFinalized();
        if (amount == 0) revert ZeroAmount();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, token, amount, nonce));

        if (withdrawalClaimed[batchId][leaf]) revert WithdrawalAlreadyClaimed();
        if (!MerkleProof.verify(merkleProof, b.withdrawalRoot, leaf)) revert InvalidProof();

        withdrawalClaimed[batchId][leaf] = true;

        if (token == address(0)) {
            (bool ok, ) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit WithdrawalClaimed(batchId, msg.sender, token, amount, nonce);
    }

    // ---------- View Helper ----------
    function batchStatus(uint256 batchId) external view returns (
        bool exists,
        bool challenged,
        bool finalized,
        uint256 submittedAt,
        uint256 challengeEndsAt,
        bytes32 prevRoot,
        bytes32 newRoot,
        bytes32 txHash,
        bytes32 withdrawalRoot,
        address challenger
    ) {
        Batch storage b = batches[batchId];
        exists = (b.submittedAt != 0);
        challenged = b.challenged;
        finalized = b.finalized;
        submittedAt = b.submittedAt;
        challengeEndsAt = b.submittedAt == 0 ? 0 : uint256(b.submittedAt) + challengeWindow;
        prevRoot = b.prevStateRoot;
        newRoot = b.newStateRoot;
        txHash = b.txDataHash;
        withdrawalRoot = b.withdrawalRoot;
        challenger = b.challenger;
    }

    receive() external payable {}
}