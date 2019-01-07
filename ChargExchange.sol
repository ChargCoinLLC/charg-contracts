
contract ChargExchange {
  
	using SafeMath for uint;

    ChargCoinContract private _instance;

	function ChargExchange(address addrChargCoinContract) public {
		_instance = ChargCoinContract(addrChargCoinContract);
    }

	struct Order {
		address user;
		uint amountGive;
		uint amountGet;
		uint expire;
	}
  
	mapping (bytes32 => Order) public sellOrders;
	mapping (bytes32 => Order) public buyOrders;
	
	mapping (address => uint) public ethBalance;
	mapping (address => uint) public coinBalance;
 

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
	
	event ChargOn (bytes32 indexed orderHash, uint amountGive, uint amountCharge, address indexed station, address indexed payer);
  
	function() public payable {
		//revert();
		depositEther();
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
		require(amount > 0 && _instance.transferFrom(msg.sender, this, amount));
		coinBalance[msg.sender] = coinBalance[msg.sender].add(amount);
		DepositCoins(msg.sender, amount, coinBalance[msg.sender]);
	}

	function withdrawCoins(uint amount) public {
		require(amount > 0 && coinBalance[msg.sender] >= amount);
		coinBalance[msg.sender] = coinBalance[msg.sender].sub(amount);
		require(_instance.transfer(msg.sender, amount));
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

	function chargOn(address station, bytes32 orderHash) public payable {
		require(block.number <= sellOrders[orderHash].expire && 0 <= sellOrders[orderHash].amountGet.sub(msg.value));
		uint amountGet = sellOrders[orderHash].amountGive.mul(msg.value) / sellOrders[orderHash].amountGet;
		require(0 <= coinBalance[sellOrders[orderHash].user].sub(amountGet) && 0 <= sellOrders[orderHash].amountGive.sub(amountGet));
		require(_instance.authorized(station)==1);
		//require(_instance.chargingSwitches(msg.sender).initialized==0);
		
		coinBalance[sellOrders[orderHash].user] = coinBalance[sellOrders[orderHash].user].sub(amountGet);
		ethBalance[sellOrders[orderHash].user] = ethBalance[sellOrders[orderHash].user].add(msg.value);
		
		sellOrders[orderHash].amountGive = sellOrders[orderHash].amountGive.sub(amountGet); 
		sellOrders[orderHash].amountGet = sellOrders[orderHash].amountGet.sub(msg.value); 

		require(_instance.transfer(station, amountGet));
		
		ChargOn (orderHash, msg.value, amountGet, station, msg.sender);
	}

}

