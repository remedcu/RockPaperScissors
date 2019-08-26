pragma solidity >=0.4.22 <0.6.0;

import "./Stoppable.sol";
import "./SafeMath.sol";

contract RockPaperScissors is Stoppable{
    using SafeMath for uint;

    struct PlayDetails {
        uint256 bet; // For storing the wager in that particular play
        uint256 deadline; // Each player has this much time till claimBack/Play
        address playerOne; // To store the player One's Address
        address playerTwo; // To store the player Two's Address
        uint256 playerTwoChoice; // To store player Two's game
    }

    uint256 public maxGamePlayTime; // Maximum amount of time for a game play from current time
    uint256 public resultTime; // Maximum amount of time for player 1 to reveal the result after which player 2 wins automatically

    mapping (address => uint256) public balances; // For storing the player balance in contract
    mapping (bytes32 => PlayDetails) public plays;

    event Deposit(address indexed playerAddress, uint256 value);
    event PlayerOne(bytes32 indexed hashValue, address playerAddress, uint256 indexed bet, uint256 indexed deadline);
    event PlayerTwo(bytes32 indexed hashValue, address indexed playerAddress, uint256 indexed choice);
    event Withdrawed(address indexed to, uint256 value);
    event Reveal(bytes32 indexed hashValue, address indexed playerAddress, uint256 indexed choice);
    event ForceReveal(bytes32 indexed hashValue, address indexed playerAddress);
    event Winner(bytes32 indexed hashValue, address indexed playerAddress);

    constructor(bool initialRunState) public Stoppable(initialRunState){
        maxGamePlayTime = 3600; // Set at 1 hour
        resultTime = 1200; // Set at 20 min
    }

    function encrypt(uint256 choice, bytes32 uniqueWord) public view returns(bytes32 hashValue){

        // 1 is Rock, 2 is Paper and 3 is Scissor
        require(choice > 0 && choice < 4, "Invalid Choice Passed");
        return keccak256(abi.encodePacked(choice, uniqueWord, address(this), msg.sender));

    }

    function playerOne(bytes32 hashValue, uint256 bet, uint256 duration, address playerTwoAddress) public onlyIfRunning payable returns(bool status){

        uint userBalance = balances[msg.sender];

        // Even though we are going a long way to make sure the hashValue will be unique
        require(plays[hashValue].playerOne == address(0), "Please choose another Unique Word");

        // This is just a particular amount of time set at the time of contract deployment
        require(duration <= maxGamePlayTime, "Each play is restricted to be max of a particular amount of time");

        require(bet > 0, "Atleast 1 wei bet is required");

        if(msg.value > 0){
            // If extra amount is sent with this transaction, to get that.
            balances[msg.sender] = userBalance.add(msg.value);
            emit Deposit(msg.sender, msg.value);
        }

        // This will also take care if bet specified was more than balance of that player
        balances[msg.sender] = userBalance.sub(bet);

        uint256 deadline = now.add(duration);

        // Play Details are added
        plays[hashValue].bet = bet;
        plays[hashValue].deadline = deadline;
        plays[hashValue].playerOne = msg.sender;
        plays[hashValue].playerTwo = playerTwoAddress;

        emit PlayerOne(hashValue, msg.sender, bet, deadline);
        return true;

    }

    function playerTwo(bytes32 hashValue, uint256 choice) public onlyIfRunning payable returns(bool status){

        require(choice > 0 && choice < 4, "Invalid Choice Passed");

        require(plays[hashValue].playerTwo == msg.sender, "Only that particular player can play this bet");

        uint256 userBalance = balances[msg.sender];
        uint256 betAmount = plays[hashValue].bet;
        uint256 deadline = plays[hashValue].deadline;

        require(deadline <= now, "Play Deadline has passed");

        if(msg.value > 0){
            // If extra amount is sent with this transaction, to get that.
            balances[msg.sender] = userBalance.add(msg.value);
            emit Deposit(msg.sender, msg.value);
        }

        require(userBalance >= betAmount, "The player don't have enough balance");
        require(plays[hashValue].playerTwoChoice == 0, "Some other player already used this hash");

        // This will also take care if betAmount specified was more than balance of that player
        balances[msg.sender] = userBalance.sub(betAmount);

        // Play Details are added
        plays[hashValue].deadline = now.add(resultTime);
        plays[hashValue].playerTwo = msg.sender;
        plays[hashValue].playerTwoChoice = choice;

        emit PlayerTwo(hashValue, msg.sender, choice);
        return true;

    }

    function reveal(uint choice, bytes32 uniqueWord) public onlyIfRunning returns(bool status){

        bytes32 hashValue = encrypt(choice, uniqueWord);

        // To make sure player 2 has played
        require(plays[hashValue].playerTwoChoice != 0, "Player 2 has not played yet");

        address won;
        address playerTwoAddress = plays[hashValue].playerTwo;
        uint256 playerTwoChoice = plays[hashValue].playerTwoChoice;

        uint256 playerOneBalance = balances[msg.sender];
        uint256 playerTwoBalance = balances[playerTwoAddress];
        uint256 playerBalance = 0;

        uint256 betAmountByTwo = plays[hashValue].bet;
        uint256 betAmount = betAmountByTwo.mul(2);
        plays[hashValue].bet = 0;

        if(choice == playerTwoChoice){
            balances[msg.sender] = playerOneBalance.add(betAmountByTwo);
            balances[playerTwoAddress] = playerTwoBalance.add(betAmountByTwo);
        }
        else if(
        (choice == 1 && playerTwoChoice == 2) ||
        (choice == 2 && playerTwoChoice == 3) ||
        (choice == 3 && playerTwoChoice == 1)){
            won = playerTwoAddress;
            playerBalance = playerTwoBalance;
        }
        else{
            won = msg.sender;
            playerBalance = playerOneBalance;
        }

        if(won != address(0)){
            balances[won] = playerBalance.add(betAmount);

            emit Reveal(hashValue, msg.sender, choice);
            emit Winner(hashValue, msg.sender);
        }

        return true;
    }

    function forceReveal(bytes32 hashValue) public onlyIfRunning returns(bool status){

        // Only the Remit Creator should be allowed to claim back
        require(plays[hashValue].playerTwo == msg.sender, "Only second player can use this function");
        require(plays[hashValue].bet != 0, "Play Ended");
        require(plays[hashValue].deadline > now, "Force Reveal period has not started yet");

        balances[msg.sender] = balances[msg.sender].add(plays[hashValue].bet.mul(2));
        plays[hashValue].bet = 0;

        emit ForceReveal(hashValue, msg.sender);
        emit Winner(hashValue, msg.sender);

        return true;
    }

    function withdraw(uint256 amount) public onlyIfRunning returns(bool status){

        require(amount > 0, "Zero cant be withdrawn");

        balances[msg.sender] = balances[msg.sender].sub(amount);

        emit Withdrawed(msg.sender, amount);

        msg.sender.transfer(amount);
        return true;

    }

}
