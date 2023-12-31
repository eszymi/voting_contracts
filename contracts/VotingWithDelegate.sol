// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VotingWithDelegateEvents {
    event NewProposer(address indexed _oldProposer, address indexed _newProposer);
    event NowProposal(uint256 indexed _numberOfProposal, uint256 _lastBlocks);
    event Delegated(address indexed _from, address indexed _to, uint256 indexed _numberOfProposal, uint256 _votes);
    event Voted(uint256 indexed _numberOfProposal, address indexed _voter, uint256 _votes, bool _yes);
    event DelegateVoted(uint256 indexed _numberOfProposal, address indexed _delegatedVoter, uint256 _votes, bool _choose);
    event NoResult(uint256 indexed _numberOfProposal);
    event Result(uint256 indexed _numberOfProposal, bool indexed _accepted);
}

contract VotingWithDelegate is VotingWithDelegateEvents {
    uint256 constant MINIMUM = 2; // minimum voters that has to take part in the voting is the total amount of the token divided by this

    address public proposer; // address which is able to create a new Proposal

    bool public locked = false;

    struct Proposal {
        bytes32 name; // short name (up to 32 bytes)
        uint256 deadline; // expiring of the proposal
        uint256 yesCount; // number of possitive votes
        uint256 noCount; // number of negative votes
    }

    Proposal[] public proposals;

    IERC20 public voteToken;

    mapping(uint256 => mapping(address => uint256)) lockedTokens;
    mapping(uint256 => mapping(address => uint256)) lockedDelegatedTokens;
    mapping(uint256 => mapping(address => uint256)) delegatedTokens;

    constructor(address voteTokenAddress) {
        voteToken = IERC20(voteTokenAddress);
        proposer = msg.sender;
    }

    modifier Proposer() {
        require(msg.sender == proposer, "Modifier: you're not proposer");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "NonReentract: locked");
        locked = true;
        _;
        locked = false;
    }

    function changeProposer(address _newProposer) public Proposer {
        proposer = _newProposer;
        emit NewProposer(msg.sender, _newProposer);
    }

    function createProposal(bytes32 _name, uint256 lastBlocks)
        public
        Proposer
        nonReentrant
        returns (uint256 numberOfProposal)
    {
        proposals.push(Proposal({name: _name, deadline: block.number + lastBlocks, yesCount: 0, noCount: 0}));
        numberOfProposal = proposals.length - 1;
        emit NowProposal(numberOfProposal, lastBlocks);
    }

    function delegate(address to, uint256 numberOfProposal, uint256 votes) public nonReentrant {
        require(voteToken.balanceOf(msg.sender) >= votes, "Delegate: not enought tokens");
        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedDelegatedTokens[numberOfProposal][msg.sender] += votes;
        delegatedTokens[numberOfProposal][to] += votes;
        emit Delegated(msg.sender, to, numberOfProposal, votes);
    }

    function vote(uint256 numberOfProposal, uint256 votes, bool choose) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "Vote: too late");

        voteToken.transferFrom(msg.sender, address(this), votes);
        lockedTokens[numberOfProposal][msg.sender] += votes;

        if (choose) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit Voted(numberOfProposal, msg.sender, votes, choose);
    }

    function delegateVote(uint256 numberOfProposal, uint256 votes, bool choose) public nonReentrant {
        require(proposals[numberOfProposal].deadline > block.number, "DelegateVote: too late");

        require(votes <= delegatedTokens[numberOfProposal][msg.sender], "DelegatedVote: too many votes");
        delegatedTokens[numberOfProposal][msg.sender] -= votes;

        if (choose) {
            proposals[numberOfProposal].yesCount += votes;
        } else {
            proposals[numberOfProposal].noCount += votes;
        }
        emit DelegateVoted(numberOfProposal, msg.sender, votes, choose);
    }

    function withdraw(uint256 numberOfProposal) public nonReentrant {
        require(proposals[numberOfProposal].deadline < block.number, "Withdraw: too early");
        uint256 lockedAmount = lockedTokens[numberOfProposal][msg.sender];
        lockedTokens[numberOfProposal][msg.sender] = 0;

        uint256 delegatedAmount = lockedDelegatedTokens[numberOfProposal][msg.sender];
        lockedDelegatedTokens[numberOfProposal][msg.sender] =  0;

        if (lockedAmount + delegatedAmount < voteToken.balanceOf(address(this))) {
            voteToken.transfer(msg.sender, lockedAmount + delegatedAmount);
        } else {
            voteToken.transfer(msg.sender, voteToken.balanceOf(address(this)));
        }
    }

    function result(uint256 numberOfProposal) public nonReentrant {
        require(proposals[numberOfProposal].deadline < block.number, "Result: too early");
        uint256 yes = proposals[numberOfProposal].yesCount;
        uint256 no = proposals[numberOfProposal].noCount;
        if (yes + no <= voteToken.totalSupply() / MINIMUM) {
            emit NoResult(numberOfProposal);
        } else {
            bool outcome = yes > no ? true : false;
            emit Result(numberOfProposal, outcome);
        }
    }
}
