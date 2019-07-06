/*
 * The Charg Service Contract
 *
 * Smart Contract handles Charg Swap Exchange, Services and Feedbacks
 *
 */

contract ChargService is Ownable {
  
	using SafeMath for uint;

    /**
	 * the CHG coins contract
	 */
    ChargCoinContract private chargCoinContractInstance;  

    /**
	 * the node main data
	 */
	struct NodeData {

		bool registered;
		bool authorized;

        /* lat, lon values, multiplied by 10^10 */
		uint32 latitude;
		uint32 longitude;
	}


    /**
	 * possible services (Charg, Parking, Internet...) 
	 */
	struct Service {
		bool allowed; // allowed in the smart contract
		string name;
	}


    /**
	 * service parameters for the particular node 
	 */
	struct ServiceData {
		bool allowed; // service allowed on the node
		uint rate;    // service rate in coins gwei for second
		uint maxTime; // max service time in seconds (0==unlimited)
		//bool returnAllowed; // return is allowed
	}


    /* service action data */
	struct ServiceAction {
		uint started;
		uint finished;
		address node;
		address payer;
		bytes32 payerHash;
		uint serviceRate;
		uint16 serviceId;
		uint16 currencyId;
		uint8 feedbackRate;
		string feedbackText;
	}

	uint16 public servicesCount = 0; 
	mapping (uint16 => Service) public services;  // the contract owner can add common services

    mapping (address => mapping (bytes32 => string)) public nodeParameters;  //node=>parametrHash=>parameterValue

    mapping (address => NodeData) public registeredNodes;

    mapping (address => mapping (uint16 => ServiceData)) public nodeService;  //node=>serviceId=>ServiceData

	mapping (bytes32 => ServiceAction) public serviceActions; // paymentHash=>ServiceAction
	
	/**
	 * collecting fees eth address 
	 */
	address private feesAccount; 


	/**
	 * minimal CHG balance for start service on the node
	 */
    uint public minCoinsBalance = 500 * 10 ** 18; //500 CHG
    

	/**
	 *   Exchange Service Structures
	 */
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

	uint16 public swapCoinsCount = 0;
	mapping (uint16 => SwapCoin) public swapCoins; // payment currencies, can be changed by owner
  
	mapping (bytes32 => Order) public sellOrders;
	mapping (bytes32 => Order) public buyOrders;
	
	mapping (address => uint) public ethBalance;
	mapping (address => uint) public coinBalance;


	/*   events    */
 	event NodeRegistered ( address addr, uint latitude, uint longitude );
	event NodeModified  ( address addr, uint latitude, uint longitude );

	event DepositEther  ( address sender, uint EthValue, uint EthBalance );
	event WithdrawEther ( address sender, uint EthValue, uint EthBalance );
	
	event DepositCoins  ( address sender, uint CoinValue, uint CoinBalance );
	event WithdrawCoins ( address sender, uint CoinValue, uint CoinBalance );
 
	event SellOrder ( bytes32 indexed orderHash, uint amountGive, uint amountGet, uint expires, address seller );
	event BuyOrder  ( bytes32 indexed orderHash, uint amountGive, uint amountGet, uint expires, address buyer );
	
	event CancelSellOrder ( bytes32 indexed orderHash );
	event CancelBuyOrder  ( bytes32 indexed orderHash );

	event Sell ( bytes32 indexed orderHash, uint amountGive, uint amountGet, address seller );
	event Buy  ( bytes32 indexed orderHash, uint amountGive, uint amountGet, address buyer );
	
	event ServiceOn  ( address indexed nodeAddr, address payer, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId, uint16 currencyId, uint chgAmount, uint serviceTime);
	event ServiceOff ( address indexed nodeAddr, address payer, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId, uint16 currencyId, uint chgAmount, uint serviceTime);
	event Feedback   ( address indexed nodeAddr, address payer, bytes32 paymentHash, bytes32 payerHash, uint16 serviceId, uint16 currencyId, uint8 feedbackRate);


	/**
	 * constructor
	 */
	function ChargService(address addrChargCoinContract) public {

		chargCoinContractInstance = ChargCoinContract(addrChargCoinContract);
		feesAccount = msg.sender;

		// default services
		services[servicesCount].name = 'Charging';
		services[servicesCount].allowed = true;
		servicesCount++;
	
		//set default fees in %
		swapCoins[swapCoinsCount].coin = 'CHG';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 0;
		swapCoinsCount++;

		swapCoins[swapCoinsCount].coin = 'ETH';
		swapCoins[swapCoinsCount].allowed = true;
		swapCoins[swapCoinsCount].fee = 1;
		swapCoinsCount++;
    }

	function() public payable {
		//revert();
		depositEther();
	}


    /* service setup, or add a new service to the smart contract */
	function setupCommonService( string name, bool allowed ) onlyOwner public {

		for (uint16 i = 0; i < servicesCount; i++) {
			if (keccak256(services[i].name)==keccak256(name)) {
				services[i].allowed = allowed;
				return;
			}
		}
		services[servicesCount].name = name;
		services[servicesCount].allowed = allowed;
		servicesCount++;
	}


    /* register a new node */
    function registerNode( uint32 latitude, uint32 longitude, string name, string location, uint chargRate) public {

        require (!registeredNodes[msg.sender].registered);
        require (chargCoinContractInstance.balanceOf(msg.sender)>minCoinsBalance);

		registeredNodes[msg.sender].registered = true;
		registeredNodes[msg.sender].authorized = true;

		registeredNodes[msg.sender].latitude = latitude;
		registeredNodes[msg.sender].longitude = longitude;

        if (chargRate > 0) {
			nodeService[msg.sender][0].allowed = true;
			nodeService[msg.sender][0].maxTime = 0;
			nodeService[msg.sender][0].rate = chargRate;
		}

		const bytes32 nameHashed = keccak256('name');
		const bytes32 locationHashed = keccak256('location');

		setNodeParameter(nameHashed, name);
		setNodeParameter(locationHashed, location);

		NodeRegistered( msg.sender, latitude, longitude );
	}


    function modifyNodeLocation(uint32 latitude, uint32 longitude) public {
        require (!registeredNodes[msg.sender].authorized);
        require (chargCoinContractInstance.balanceOf(msg.sender)>minCoinsBalance);

		registeredNodes[msg.sender].latitude = latitude;
		registeredNodes[msg.sender].longitude = longitude;

		NodeModified( msg.sender, latitude, longitude );
    }
    

    /* setup the node parameters */
    function setNodeParameter(bytes32 parameterHash, string parameterValue) public {
        //require (registeredNodes[msg.sender].authorized);
        nodeParameters[msg.sender][parameterHash] = parameterValue;
    }
	

    /* setup the node services */
	function setupNodeService( uint16 serviceId, bool allowed, uint rate, uint maxTime ) public {

        require (registeredNodes[msg.sender].authorized);
        require (serviceId < servicesCount);

        nodeService[msg.sender][serviceId].allowed = allowed;
        nodeService[msg.sender][serviceId].rate = rate;
        nodeService[msg.sender][serviceId].maxTime = maxTime;

	}


    /* change the node authorization */ 
    function modifyNodeAuthorization (address addr, bool authorized) onlyOwner public {
        require (registeredNodes[msg.sender].registered);
        registeredNodes[addr].authorized = authorized;
    }


    /* set minimal coins balance for the node */ 
    function setMinCoinsBalance(uint _newValue) onlyOwner public {
		minCoinsBalance = _newValue;
	}


    /* set fees account */ 
	function setFeesAccount( address addrFeesAccount ) onlyOwner public {
		feesAccount = addrFeesAccount;
	}


    /* set fee or add a new currency */ 
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
		
		uint amountGet; //in CHG
		
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
	 * nodeAddr - the node which provides service
	 * serviceId - id of the started service, described in Node Service Contract (0-charge, 1-parking, 2-internet ...)
	 * currencyId - id of payment currency/coins ( 0-CHG, 1-ETH, 2-BTC, 3-LTC, 4-USD, ... check swapCoins )
	 * orderHash - hash of exchange sell order 
	 * payerHash - hashed payer identificator (MAC, Cookie ID, etc...)
	 * paymentHash - hash of the payment transaction 
	 */
	function serviceOn(address nodeAddr, uint16 serviceId, uint16 currencyId, uint time, bytes32 orderHash, bytes32 payerHash, bytes32 paymentHash) public payable returns (bytes32) {

		require ( registeredNodes[nodeAddr].authorized          // the node is registered and authorized
				&& (chargCoinContractInstance.balanceOf(nodeAddr)>minCoinsBalance) // minimal balance of the node
				&& swapCoins[currencyId].allowed                // currency is allowed
				&& nodeService[nodeAddr][serviceId].allowed );  // sevice is allowed on the node

		if (paymentHash==0)
			paymentHash = keccak256(msg.sender, now, serviceId);

		require ( serviceActions[paymentHash].started == 0 );

		if (payerHash==0)
			payerHash = keccak256(msg.sender);

		uint chgAmount;

		if (currencyId > 0) {  //need exchange
			require( msg.value > 0 );

			uint feeAmount = msg.value.mul(swapCoins[currencyId].fee).div(100);
			uint ethAmount = msg.value - feeAmount;

			require(block.number <= sellOrders[orderHash].expire && 0 <= sellOrders[orderHash].amountGet.sub(ethAmount));

			require(0 <= coinBalance[sellOrders[orderHash].user].sub(chgAmount) && 0 <= sellOrders[orderHash].amountGive.sub(chgAmount));

			if (ethAmount==sellOrders[orderHash].amountGet) {
				chgAmount = sellOrders[orderHash].amountGive;
				require(0 <= coinBalance[sellOrders[orderHash].user].sub(chgAmount));
				sellOrders[orderHash].amountGive = 0; 
				sellOrders[orderHash].amountGet = 0; 
				sellOrders[orderHash].expire = 0; 
			} else {
				chgAmount = sellOrders[orderHash].amountGive.mul(ethAmount) / sellOrders[orderHash].amountGet;
				require(0 <= coinBalance[sellOrders[orderHash].user].sub(chgAmount) && 0 <= sellOrders[orderHash].amountGive.sub(chgAmount));
				sellOrders[orderHash].amountGive = sellOrders[orderHash].amountGive.sub(chgAmount); 
				sellOrders[orderHash].amountGet = sellOrders[orderHash].amountGet.sub(ethAmount); 
			}

			// time will be calculated by amount
			time = chgAmount.div(nodeService[nodeAddr][serviceId].rate);
			require ( time <= nodeService[nodeAddr][serviceId].maxTime || nodeService[nodeAddr][serviceId].maxTime == 0);

			coinBalance[sellOrders[orderHash].user] = coinBalance[sellOrders[orderHash].user].sub(chgAmount);
			ethBalance[sellOrders[orderHash].user] = ethBalance[sellOrders[orderHash].user].add(ethAmount);
			
			if (feeAmount > 0) {
				ethBalance[feesAccount] = ethBalance[feesAccount].add(feeAmount);
			} 

			Buy(orderHash, sellOrders[orderHash].amountGive, sellOrders[orderHash].amountGet, msg.sender);
		
		} else {  // CHG payment
			require ( time <= nodeService[nodeAddr][serviceId].maxTime || nodeService[nodeAddr][serviceId].maxTime == 0);
			chgAmount = time * nodeService[nodeAddr][serviceId].rate;
			require( chgAmount > 0 && 0 <= coinBalance[msg.sender].sub(chgAmount) );
			coinBalance[msg.sender] = coinBalance[msg.sender].sub(chgAmount);
		}

		//require(chargCoinContractInstance.transfer(nodeAddr, chgAmount));
		coinBalance[nodeAddr] = coinBalance[nodeAddr].add(chgAmount); 

		if (serviceActions[paymentHash].started==0) {
			serviceActions[paymentHash].node = nodeAddr; 
			serviceActions[paymentHash].payer = msg.sender; //will allow feedback for the sender
			serviceActions[paymentHash].payerHash = payerHash; //example: car plate number, MAC address
			serviceActions[paymentHash].currencyId = currencyId;
			serviceActions[paymentHash].serviceRate = nodeService[nodeAddr][serviceId].rate;
			serviceActions[paymentHash].serviceId = serviceId;
			serviceActions[paymentHash].started = now;
			serviceActions[paymentHash].finished = now + time;
		}

		ServiceOn (nodeAddr, msg.sender, paymentHash, payerHash, serviceId, currencyId, chgAmount, time);

		return paymentHash;
	}

	
	/*
	 * Method serviceOff
	 * Turn off the service on the node
	 */
	function serviceOff( bytes32 paymentHash ) public {

		require(serviceActions[paymentHash].started > 0 
					&& now < serviceActions[paymentHash].finished 
					&& serviceActions[paymentHash].payer == msg.sender);

		uint time = serviceActions[paymentHash].finished.sub(now);
		uint chgAmount = time.mul(serviceActions[paymentHash].serviceRate);

        if (serviceActions[paymentHash].currencyId==0 ) { //CHG coins
			coinBalance[serviceActions[paymentHash].node] = coinBalance[serviceActions[paymentHash].node].sub(chgAmount);
			coinBalance[msg.sender] = coinBalance[msg.sender].add(chgAmount);
        } 
		// else swap exchange, listen to the event, implemented on the node
        
		ServiceOff (serviceActions[paymentHash].node, msg.sender, paymentHash, serviceActions[paymentHash].payerHash, serviceActions[paymentHash].serviceId, serviceActions[paymentHash].currencyId, chgAmount, time);
	}


	/*
	 * Method sendFeedback
	 * Store feedback on the successful payment transaction in the smart contract
	 * paymentHash - hash of the payment transaction
	 * rate - the node raiting 1..5 points 
	 */
	function sendFeedback(bytes32 paymentHash, uint8 feedbackRate, string feedbackText) public {

		require(serviceActions[paymentHash].payer==msg.sender && serviceActions[paymentHash].feedbackRate==0);

		serviceActions[paymentHash].feedbackRate = feedbackRate > 5 ? 5 : (feedbackRate < 1 ? 1 : feedbackRate);
		serviceActions[paymentHash].feedbackText = feedbackText;
		
		Feedback (serviceActions[paymentHash].node, msg.sender, paymentHash, serviceActions[paymentHash].payerHash, serviceActions[paymentHash].serviceId, serviceActions[paymentHash].currencyId, serviceActions[paymentHash].feedbackRate);
	}
}

