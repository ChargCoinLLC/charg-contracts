
/*
 * ChargExchange
 *
 * Smart Contract handles Charg Swap Exchange, Services and Feedbacks
 *
 */

contract ChargExchange is Ownable {
  
	using SafeMath for uint;

    ChargCoinContract private chargCoinContractInstance;
	address private feesAccount; 

	function ChargExchange(address addrChargCoinContract) public {

		chargCoinContractInstance = ChargCoinContract(addrChargCoinContract);
		feesAccount = msg.sender;

		//set default service fees in %
		swapCoins[swapCoinsCount].coin = 'CHG';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 0;
		swapCoinsCount++;

		swapCoins[swapCoinsCount].coin = 'ETH';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 1;
		swapCoinsCount++;

		swapCoins[swapCoinsCount].coin = 'BTC';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 2;
		swapCoinsCount++;

		swapCoins[swapCoinsCount].coin = 'LTC';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 2;
		swapCoinsCount++;

		swapCoins[swapCoinsCount].coin = 'USD';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 4;
		swapCoinsCount++;
		
    }

	struct Order {
		address user;
		uint amountGive;
		uint amountGet;
		uint expire;
	}

	struct SwapCoin {
		bool allowed;
		uint fee;
		string coin;
	}
	
	struct Feedback {
		bool enabled;
		bool completed;
		uint8 rate;
		address sender;
		uint16 serviceId;
		string message;
	}

	uint16 public swapCoinsCount = 0;
	mapping (uint16 => SwapCoin) public swapCoins; // payment currencies fees
  
	mapping (bytes32 => Feedback) public feedbacks; // paymentHash=>Feedback

	mapping (bytes32 => Order) public sellOrders;
	mapping (bytes32 => Order) public buyOrders;
	
	mapping (address => uint) public ethBalance;
	mapping (address => uint) public coinBalance;
 

	// events
	event DepositEther(address sender, uint EthValue, uint EthBalance);
	event WithdrawEther(address sender, uint EthValue, uint EthBalance);
	
	event DepositCoins(address sender, uint CoinValue, uint CoinBalance);
	event WithdrawCoins(address sender, uint CoinValue, uint CoinBalance);
 
	event SellOrder(bytes32 indexed orderHash, uint amountGive, uint amountGet, uint expires, address seller);
	event BuyOrder (bytes32 indexed orderHash, uint amountGive, uint amountGet, uint expires, address buyer);
	
	event CancelSellOrder(bytes32 indexed orderHash);
	event CancelBuyOrder(bytes32 indexed orderHash);

	event Sell(bytes32 indexed orderHash, uint amountGive, uint amountGet, address seller);
	event Buy (bytes32 indexed orderHash, uint amountGive, uint amountGet, address buyer);
	
	event ServiceOn ( address indexed node, address indexed payer, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId, uint16 currencyId, uint amount);
	event ServiceOff (address indexed node, address indexed payer, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId);

	function() public payable {
		//revert();
		depositEther();
	}

	function setFeesAccount( address addrFeesAccount ) onlyOwner public {
		feesAccount = addrFeesAccount;
	}

	function setFee( string coin, uint8 fee, bool allowed ) onlyOwner public {

		for (uint16 i = 0; i < swapCoinsCount; i++) {
			if (keccak256(swapCoins[i].coin)==keccak256(coin)) {
				swapCoins[i].allowed = allowed;
				swapCoins[i].fee = fee;
				return;
			}
		}

		swapCoins[swapCoinsCount].coin = coin;
		swapCoins[swapCoinsCount].allowed = allowed;
		swapCoins[swapCoinsCount].fee = fee;
		swapCoinsCount++;
	}

	function tokenFallback( address sender, uint amount, bytes data) public returns (bool ok) {
		return true;
	}
	
	function depositEther() public payable {
		ethBalance[msg.sender] = ethBalance[msg.sender].add(msg.value);
		DepositEther(msg.sender, msg.value, ethBalance[msg.sender]);
	}

	function withdrawEther(uint amount) public {
		require(ethBalance[msg.sender] >= amount);
		ethBalance[msg.sender] = ethBalance[msg.sender].sub(amount);
		msg.sender.transfer(amount);
		WithdrawEther(msg.sender, amount, ethBalance[msg.sender]);
	}

	function depositCoins(uint amount) public {
		require(amount > 0 && chargCoinContractInstance.transferFrom(msg.sender, this, amount));
		coinBalance[msg.sender] = coinBalance[msg.sender].add(amount);
		DepositCoins(msg.sender, amount, coinBalance[msg.sender]);
	}

	function withdrawCoins(uint amount) public {
		require(amount > 0 && coinBalance[msg.sender] >= amount);
		coinBalance[msg.sender] = coinBalance[msg.sender].sub(amount);
		require(chargCoinContractInstance.transfer(msg.sender, amount));
		WithdrawCoins(msg.sender, amount, coinBalance[msg.sender]);
	}

	function buyOrder(uint amountGive, uint amountGet, uint expire) public {
		require(amountGive > 0 && amountGet > 0 && amountGive <= ethBalance[msg.sender]);
		bytes32 orderHash = sha256(this, amountGive, amountGet, block.number+expire, block.number);
		buyOrders[orderHash] = Order(msg.sender, amountGive, amountGet, block.number+expire);
		BuyOrder(orderHash, amountGive, amountGet, block.number+expire, msg.sender);
	}

	function sellOrder(uint amountGive, uint amountGet, uint expire) public {
		require(amountGive > 0 && amountGet > 0 && amountGive <= coinBalance[msg.sender]);
		bytes32 orderHash = sha256(this, amountGive, amountGet, block.number+expire, block.number);
		sellOrders[orderHash] = Order(msg.sender, amountGive, amountGet, block.number+expire);
		SellOrder(orderHash, amountGive, amountGet, block.number+expire, msg.sender);
	}

	function cancelBuyOrder(bytes32 orderHash) public {
		require( buyOrders[orderHash].expire > block.number && buyOrders[orderHash].user == msg.sender);
		buyOrders[orderHash].expire = 0; 
		CancelBuyOrder(orderHash);
	}

	function cancelSellOrder(bytes32 orderHash) public {
		require( sellOrders[orderHash].expire > block.number && sellOrders[orderHash].user == msg.sender);
		sellOrders[orderHash].expire = 0; 
		CancelSellOrder(orderHash);
	}
	
	function buy(bytes32 orderHash, uint amountGive) public {
		require(amountGive > 0 && block.number <= sellOrders[orderHash].expire && 0 <= ethBalance[msg.sender].sub(amountGive) &&  0 <= sellOrders[orderHash].amountGet.sub(amountGive));
		
		uint amountGet;
		
		if (amountGive==sellOrders[orderHash].amountGet) {
			amountGet = sellOrders[orderHash].amountGive;
			require(0 <= coinBalance[sellOrders[orderHash].user].sub(amountGet));
			sellOrders[orderHash].amountGive = 0; 
			sellOrders[orderHash].amountGet = 0; 
			sellOrders[orderHash].expire = 0; 
		} else {
			amountGet = sellOrders[orderHash].amountGive.mul(amountGive) / sellOrders[orderHash].amountGet;
			require(0 <= coinBalance[sellOrders[orderHash].user].sub(amountGet) && 0 <= sellOrders[orderHash].amountGive.sub(amountGet));
			sellOrders[orderHash].amountGive = sellOrders[orderHash].amountGive.sub(amountGet); 
			sellOrders[orderHash].amountGet = sellOrders[orderHash].amountGet.sub(amountGive); 
		}
			
		coinBalance[sellOrders[orderHash].user] = coinBalance[sellOrders[orderHash].user].sub(amountGet);
		coinBalance[msg.sender] = coinBalance[msg.sender].add(amountGet);
			
		ethBalance[sellOrders[orderHash].user] = ethBalance[sellOrders[orderHash].user].add(amountGive);
		ethBalance[msg.sender] = ethBalance[msg.sender].sub(amountGive);

		Buy(orderHash, sellOrders[orderHash].amountGive, sellOrders[orderHash].amountGet, msg.sender);
	}
	
	function sell(bytes32 orderHash, uint amountGive) public {
		require(amountGive > 0 && block.number <= buyOrders[orderHash].expire && 0 <= coinBalance[msg.sender].sub(amountGive) &&  0 <= buyOrders[orderHash].amountGet.sub(amountGive));

		uint amountGet;

		if (amountGive==buyOrders[orderHash].amountGet) {
			amountGet = buyOrders[orderHash].amountGive;
			require(0 <= ethBalance[buyOrders[orderHash].user].sub(amountGet));
			buyOrders[orderHash].amountGive = 0; 
			buyOrders[orderHash].amountGet = 0; 
			buyOrders[orderHash].expire = 0; 
		} else {
			amountGet = buyOrders[orderHash].amountGive.mul(amountGive) / buyOrders[orderHash].amountGet;
			require(0 <= ethBalance[buyOrders[orderHash].user].sub(amountGet) && 0 <= buyOrders[orderHash].amountGive.sub(amountGet));
			buyOrders[orderHash].amountGive = buyOrders[orderHash].amountGive.sub(amountGet); 
			buyOrders[orderHash].amountGet = buyOrders[orderHash].amountGet.sub(amountGive); 
		}

		ethBalance[buyOrders[orderHash].user] = ethBalance[buyOrders[orderHash].user].sub(amountGet);
		ethBalance[msg.sender] = ethBalance[msg.sender].add(amountGet);
			
		coinBalance[buyOrders[orderHash].user] = coinBalance[buyOrders[orderHash].user].add(amountGive);
		coinBalance[msg.sender] = coinBalance[msg.sender].sub(amountGive);
		
		Sell(orderHash, buyOrders[orderHash].amountGive, buyOrders[orderHash].amountGet, msg.sender);
	}

	/*
	 * Method serviceOn
	 * Make an exchange and start service on the node
	 *
	 * node - the node which provides service
	 * orderHash - hash of exchange sell order 
	 * paymentHash - any hashed payment data (another network transaction id, confirmation c/c payment check id, etc...  )
	 * payerHash - hashed payer identificator (MAC, Cookie ID, etc...)
	 * serviceId - id of the started service, described in Node Service Contract (0-charge, 1-parking, 2-internet ...)
	 * currencyId - id of payment currency/coins (0-CHG, 1-ETH, 2-BTC, 3-LTC, 4-USD, ...)
	 */
	function serviceOn(address node, bytes32 orderHash, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId, uint16 currencyId) public payable {

		require((currencyId > 0) && swapCoins[currencyId].allowed ); // if currencyId==0 then CHG, no need to exchange
		require(chargCoinContractInstance.authorized(node)==1);
		//require(chargNodesContractInstance.node(node).authorized);
		//require(chargCoinContractInstance.chargingSwitches(node).initialized==0);//check if charging is not started by the CHG coins contract

		uint feeAmount = msg.value.mul(swapCoins[currencyId].fee).div(100);
		uint ethAmount = msg.value - feeAmount;
		require(block.number <= sellOrders[orderHash].expire && 0 <= sellOrders[orderHash].amountGet.sub(ethAmount));

		uint amountGet = sellOrders[orderHash].amountGive.mul(ethAmount) / sellOrders[orderHash].amountGet;
		require(0 <= coinBalance[sellOrders[orderHash].user].sub(amountGet) && 0 <= sellOrders[orderHash].amountGive.sub(amountGet));

		coinBalance[sellOrders[orderHash].user] = coinBalance[sellOrders[orderHash].user].sub(amountGet);
		ethBalance[sellOrders[orderHash].user] = ethBalance[sellOrders[orderHash].user].add(ethAmount);
		
		sellOrders[orderHash].amountGive = sellOrders[orderHash].amountGive.sub(amountGet); 
		sellOrders[orderHash].amountGet = sellOrders[orderHash].amountGet.sub(ethAmount); 

		if (feeAmount > 0) {
			ethBalance[feesAccount] = ethBalance[feesAccount].add(feeAmount);
		} 

		if (!feedbacks[paymentHash].enabled) {
			feedbacks[paymentHash].sender = msg.sender; //allow feedback for the sender
			feedbacks[paymentHash].serviceId = serviceId;
			feedbacks[paymentHash].enabled = true;
		}

		require(chargCoinContractInstance.transfer(node, amountGet));

		Buy(orderHash, sellOrders[orderHash].amountGive, sellOrders[orderHash].amountGet, msg.sender);
		ServiceOn (node, msg.sender, paymentHash, payerHash, serviceId, currencyId, amountGet);
	}

	/*
	 * Method serviceOn
	 * Start service on the node for CHG coins without an exchange
	 * node - the node which provides service
	 */
	function serviceOn(address node, uint amountCHG, uint16 serviceId) public payable {
		//require(swapCoins[0].allowed ); // always allow service in CHG coins
		require((amountCHG > 0) && (chargCoinContractInstance.authorized(node)==1));
		//require(chargNodesContractInstance.authorized(node));
		//require(chargCoinContractInstance.chargingSwitches(node).initialized==0);//charging is not started by the CHG coins contract

		//uint feeAmount = amountCHG.mul(swapCoins[0].fee / 100); // no fee for service in CHG coins
		//require(0 <= coinBalance[msg.sender].sub(amountCHG));

        /*
        if (serviceId==0) { //charging
            uint rateOfCharging = chargCoinContractInstance.rateOfCharging(node);
            uint timeOfCharging = amountCHG.div(rateOfCharging);
    		require(timeOfCharging>0);
    		chargCoinContractInstance.chargeOn(node, timeOfCharging);
        } else if (serviceId==1) { //parking
            uint rateOfParking = chargCoinContractInstance.rateOfParking(node);
            uint timeOfParking = amountCHG.div(rateOfParking);
    		require(timeOfParking>0);
    		chargCoinContractInstance.parkingOn(node, timeOfParking);
        } else {
		    require(chargCoinContractInstance.transferFrom(msg.sender, this, amountCHG));
		    require(chargCoinContractInstance.transfer(node, amountCHG));
        }
        */
		bytes32 paymentHash = keccak256(block.number);
		bytes32 payerHash = keccak256(msg.sender);

		coinBalance[msg.sender] = coinBalance[msg.sender].sub(amountCHG);
		coinBalance[node] = coinBalance[node].add(amountCHG);

		if (!feedbacks[paymentHash].enabled) {
			feedbacks[paymentHash].sender = msg.sender; //allow feedback for the sender
			feedbacks[paymentHash].serviceId = serviceId;
			feedbacks[paymentHash].enabled = true;
		}

		ServiceOn (node, msg.sender, paymentHash, payerHash, serviceId, 0, amountCHG);
	}
	
	/*
	 * Method serviceOff
	 * Turn off the serviceon the node
	 */
	function serviceOff(address node, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId) public payable {

        /*
        if (serviceId==0) { //charging
    		chargCoinContractInstance.chargeOff(node);
        } else if (serviceId==1) { //parking
    		chargCoinContractInstance.parkingOff(node);
        }
        */
        
		ServiceOff (node, msg.sender, paymentHash, payerHash, serviceId);
	}


	/*
	 * Method sendFeedback
	 * Store feedback on the successful payment transaction in the smart contract
	 * paymentHash - hash of the payment transaction
	 * rate - the node raiting 0..5 points 
	 */
	function sendFeedback(bytes32 paymentHash, uint8 rate, string message) public {

		require(feedbacks[paymentHash].sender==msg.sender);
		feedbacks[paymentHash].completed = true;
		feedbacks[paymentHash].rate = rate > 5 ? 5 : rate;
		feedbacks[paymentHash].message = message;
	}
}

