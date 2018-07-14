pragma solidity ^0.4.23;

contract owned {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnerShip(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}
contract ContestController is owned {
    
    event NewContest(string title, bytes32 contestHash);
    event MembershipChanged(string memberName, address member, bool isMember);
    event NewCandidature(string contestTitle, string candidatureTitle);
    event NewVote(string member, string contestTitle, string candidatureTitle);
    event CandidatureCancellation(string member, string contestTitle, string candidatureTitle, string reason);

    struct Candidature {
        address owner;
        string title;
        uint256 votes;
        bytes32 ipfsHash;
        uint256 taxBalance;
        bool cancelled;
        address cancelledByMember;
        string reasonForCancellation;
        //....
    }

    struct Member {
        address member;
        string name;
        bytes32 candidatureHash;
    }
    
    struct Contest {
        mapping (bytes32 => Candidature) candidatures;
        bytes32[] candidaturesAccounts;
        
        mapping(address => uint) memberId;
        Member[] members;
        /**
         * Contest Stages
         * | New Contest | Member Revision | New Candidatures | Voting time | End Contest |
         */
        string title;
        string tags;
        uint256 dateLimitForMemberRevision;
        uint256 dateLimitForCandidatures;
        uint256 dateEndContest;
        uint256 limitCandidatures; // 0 for infinite
        bytes32 ipfsHash; 
        uint256 taxForCandidatures;
        uint256 award;

        // Actual winner status after each vote
        uint256 actualWinnerVotes;
        bytes32 actualWinnerAccount;
    }
    
    mapping (bytes32  => Contest) private contests;
    bytes32[] contestAccounts; // array with all contests owner accounts
    
    /*************************************************************
     *                         CONTESTS                          *
     *************************************************************/

    /**
    *
    * Create New contest
    * 
    * Set new contest with settings
    * 
 
    *
    * @param title title contest
    * @param tags tags for category
    * @param dateLimitForMemberRevision limit date for member revision
    * @param dateLimitForCandidatures limit date for new candidatures 
    * @param dateEndContest contest end date
    * @param limitCandidatures limit candidatures for contest. 0 = unlimited
    * @param taxForCandidatures required tax for each candidature
    * @param ipfsHash hash for photo set in ipfs
    */
    function setNewContest(
        string title, 
        string tags,
        uint256 dateLimitForMemberRevision, 
        uint256 dateLimitForCandidatures, 
        uint256 dateEndContest, 
        uint256 limitCandidatures,
        uint256 taxForCandidatures,
        bytes32 ipfsHash) public payable {
        
        require(msg.value > 0);
        bytes32 contestHash = keccak256(abi.encodePacked(msg.sender,title,dateEndContest));
        require(contests[contestHash].award == 0);
        require(dateLimitForMemberRevision < dateLimitForCandidatures);
        require(dateLimitForCandidatures < dateEndContest);
        
        Contest memory contest = contests[contestHash];
        
        contest.title = title;
        contest.tags = tags;
        contest.ipfsHash = ipfsHash;
        contest.dateLimitForMemberRevision = dateLimitForMemberRevision;
        contest.dateLimitForCandidatures = dateLimitForCandidatures;
        contest.dateEndContest = dateEndContest;
        contest.limitCandidatures = limitCandidatures;
        contest.taxForCandidatures = taxForCandidatures;
        contest.award = msg.value;
        
        contest.actualWinnerVotes = 0;
        // it's necessary to add an empty first member
        addMember(contestHash,0,"");
        // and let's add the founder, to save a step later
        addMember(contestHash,owner,"founder");

        contestAccounts.push(contestHash) - 1;  
        emit NewContest(title, contestHash);                      
    }

    /**
    *
    * Return contest based in '_contestHash' param
    *
    * @param contestHash contest hash to return
    */
    function getContest(bytes32 contestHash) public view 
        returns (
            string title, 
            string tags,
            uint256 dateLimitForMemberRevision, 
            uint256 dateLimitForCandidatures, 
            uint256 dateEndContest, 
            uint256 limitCandidatures,
            bytes32 ipfsHash,
            uint256 taxForCandidatures,
            uint256 award, 
            uint256 candidaturesCount) {
        
        title = contests[contestHash].title;
        tags = contests[contestHash].tags;
        dateLimitForMemberRevision = contests[contestHash].dateLimitForMemberRevision; 
        dateLimitForCandidatures = contests[contestHash].dateLimitForCandidatures; 
        dateEndContest = contests[contestHash].dateEndContest;
        limitCandidatures = contests[contestHash].limitCandidatures;
        ipfsHash = contests[contestHash].ipfsHash;
        taxForCandidatures = contests[contestHash].taxForCandidatures;
        award = contests[contestHash].award; 
        candidaturesCount = contests[contestHash].candidaturesAccounts.length;
    }

    function getTotalContestsCount() public view returns (uint256 contestsCount) {
        return contestAccounts.length;
    }

    /*************************************************************
     *                         JUDGE MEMBERS                     *
     *************************************************************/
     
    /**
    *
    * Add judge member
    * 
    * Make 'targetMember' a member named 'memberName'
    * 
    * @param contestHash contest hash
    * @param targetMember judge ethereum address
    * @param memberName judge name
    */
    function addMember(bytes32 contestHash, address targetMember, string memberName) onlyOwner public {
        require(now < contests[contestHash].dateLimitForMemberRevision);

        uint id = contests[contestHash].memberId[targetMember];
        // check new member not exists
        if (id==0) {
            contests[contestHash].memberId[targetMember] = contests[contestHash].members.length;
            id = contests[contestHash].members.length++;
        }

        Member memory judge = contests[contestHash].members[id];
        judge.member = targetMember;
        judge.name = memberName;

        contests[contestHash].members[id] = judge; //Member({member:targetMember, name: memberName});
        emit MembershipChanged(memberName, targetMember, true);
    }
    
    /**
    *
    * Remove judge member
    *
    * @notice Remove membership from 'targetMember'
    *
    * @param contestHash contest hash
    * @param targetMember judge ethereum address to be removed 
    */
    function removeMember(bytes32 contestHash, address targetMember) onlyOwner public {
        require(now < contests[contestHash].dateLimitForMemberRevision);
        require(contests[contestHash].memberId[targetMember] != 0);
        
        string memory memberName = contests[contestHash].members[contests[contestHash].memberId[targetMember]].name;

        for (uint i = contests[contestHash].memberId[targetMember]; i < contests[contestHash].members.length - 1; i++){
            contests[contestHash].members[i] = contests[contestHash].members[i + 1];
        }
        
        delete contests[contestHash].members[contests[contestHash].members.length - 1];
        contests[contestHash].members.length--;
        emit MembershipChanged(memberName, targetMember, false);
    }

    /*************************************************************
     *                        CANDIDATURES                       *
     *************************************************************/

/**
    *
    * Add new candidature
    *
    * @param contestHash contest hash for candidature
    * @param title title for candidature
    */
    function setNewCandidature(bytes32 contestHash, string title, bytes32 ipfsHash) public payable{
        require(msg.value >= contests[contestHash].taxForCandidatures);
        
        // checking limit candidatures
        require((contests[contestHash].limitCandidatures == 0) || (contests[contestHash].candidaturesAccounts.length < contests[contestHash].limitCandidatures - 1));
        
        require(now > contests[contestHash].dateLimitForMemberRevision); 
        require(now < contests[contestHash].dateLimitForCandidatures);

        bytes32 candidatureHash = keccak256(abi.encodePacked(msg.sender,title));
        contests[contestHash].candidaturesAccounts.push(candidatureHash);
        contests[contestHash].candidatures[candidatureHash].owner = msg.sender;
        contests[contestHash].candidatures[candidatureHash].title = title;
        contests[contestHash].candidatures[candidatureHash].ipfsHash = ipfsHash;
        contests[contestHash].candidatures[candidatureHash].taxBalance = msg.value;
        contests[contestHash].candidatures[candidatureHash].cancelled = false;

        emit NewCandidature(contests[contestHash].title, title);
    }
    
    function getCandidature(bytes32 contestHash, bytes32 candidatureHash) public view returns(string title, uint256 votes){
        title = contests[contestHash].candidatures[candidatureHash].title;
        votes = contests[contestHash].candidatures[candidatureHash].votes;
    }

    function getCandidaturesByContest(bytes32 contestHash) public view returns(bytes32[] candidaturesAccounts){
        return contests[contestHash].candidaturesAccounts;
    }
    
    function getTotalCandidaturesByContest(bytes32 contestHash) public view returns(uint256 candidaturesCount){
        return contests[contestHash].candidaturesAccounts.length;
    }

    function cancelCandidature(bytes32 contestHash, bytes32 candidatureHash, string reason) public {
        uint id = contests[contestHash].memberId[msg.sender];
        require(id != 0);
        require(!contests[contestHash].candidatures[candidatureHash].cancelled);

        contests[contestHash].candidatures[candidatureHash].taxBalance = 0;
        contests[contestHash].candidatures[candidatureHash].cancelled = true;
        contests[contestHash].candidatures[candidatureHash].cancelledByMember = contests[contestHash].members[id].member;
        contests[contestHash].candidatures[candidatureHash].reasonForCancellation = reason;
        
        emit CandidatureCancellation(
            contests[contestHash].members[id].name,
            contests[contestHash].title,
            contests[contestHash].candidatures[candidatureHash].title,
            reason);
    }

    /*************************************************************
     *                          VOTES                            *
     *************************************************************/

    function setNewVote(bytes32 contestHash,bytes32 candidatureHash) public {
        require(now > contests[contestHash].dateLimitForCandidatures); 
        require(now < contests[contestHash].dateEndContest);
        uint id = contests[contestHash].memberId[msg.sender];
        require(id != 0);
        require(contests[contestHash].members[id].candidatureHash[0] != 0);

        contests[contestHash].members[id].candidatureHash = candidatureHash;
        contests[contestHash].candidatures[candidatureHash].votes += 1;
        
        // refresh actual winner status
        if (contests[contestHash].candidatures[candidatureHash].votes >= contests[contestHash].actualWinnerVotes){
            contests[contestHash].actualWinnerVotes = contests[contestHash].candidatures[candidatureHash].votes;
            contests[contestHash].actualWinnerAccount = candidatureHash;
        }

        emit NewVote(
            contests[contestHash].members[id].name, 
            contests[contestHash].title,
            contests[contestHash].candidatures[candidatureHash].title);
    }

    function solveContest(bytes32 contestHash) public view returns (address _addressWinner, uint256 totalVotes) {
        require(contests[contestHash].award > 0);
        require(now > contests[contestHash].dateEndContest);
        
        return (
            contests[contestHash].candidatures[contests[contestHash].actualWinnerAccount].owner, 
            contests[contestHash].actualWinnerVotes);
    }
    
    function payToWinner(bytes32 contestHash) public {
        assert(now >= contests[contestHash].dateEndContest);
        assert(msg.sender == contests[contestHash].candidatures[contests[contestHash].actualWinnerAccount].owner);
        assert(contests[contestHash].award > 0);
        
        uint256 amount = contests[contestHash].award;
        contests[contestHash].award = 0;
        msg.sender.transfer(amount);
    }
    

     /************************************************************
     *                       PAGINATION                          *
     *************************************************************/

    function fetchContestsPage(uint256 cursor, uint256 howMany) public view returns (bytes32[] values)
    {
        require(contestAccounts.length > 0);
        require(cursor < contestAccounts.length - 1);
        
        uint256 i;
        
        if (cursor + howMany < contestAccounts.length){
            values = new bytes32[](howMany);
            for (i = 0; i < howMany; i++) {
                values[i] = contestAccounts[i + cursor];
            }
            
        } else {
            uint256 lastPageLength = contestAccounts.length - cursor;
            values = new bytes32[](lastPageLength);
            for (i = 0; i < lastPageLength; i++) {
                values[i] = contestAccounts[cursor + i];
            }
        }
        
        return (values);
    }
    
    function fetchCandidaturesPage(bytes32 _contestHash, uint256 cursor, uint256 howMany) public view returns (bytes32[] values)
    {
        require(contests[_contestHash].award > 0);
        require(contests[_contestHash].candidaturesAccounts.length > 0);
        require(cursor < contests[_contestHash].candidaturesAccounts.length - 1);
        
        uint256 i;
        
        if (cursor + howMany < contests[_contestHash].candidaturesAccounts.length){
            values = new bytes32[](howMany);
            for (i = 0; i < howMany; i++) {
                values[i] = contests[_contestHash].candidaturesAccounts[i + cursor];
            }
            
        } else {
            uint256 lastPageLength = contestAccounts.length - cursor;
            values = new bytes32[](lastPageLength);
            for (i = 0; i < lastPageLength; i++) {
                values[i] = contests[_contestHash].candidaturesAccounts[cursor + i];
            }
        }
        
        return (values);
    }
    
    // only for date testing purposes
    function getTimeNow() public view returns(uint256){
        return now;
    }
} 