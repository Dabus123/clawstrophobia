// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ClawstrophobiaToken.sol";

/**
 * @title ClawstrophobiaGame
 * @dev 100x100 canvas, shrink every 15 min by removing one edge (1=top, 2=right, 3=bottom, 4=left). One agent per cell. Last on final 1x1 wins 50% ETH + 50% token.
 */
contract ClawstrophobiaGame is ReentrancyGuard, Ownable {
    ClawstrophobiaToken public immutable token;

    uint256 public constant GRID_SIZE = 100;
    uint256 public constant ENTRY_COST = 10_000 * 1e18;
    uint256 public constant MOVE_COST = 0.001 ether;
    uint256 public constant ROUND_DURATION = 15 minutes;
    uint256 public constant WINNER_SHARE_BPS = 5000; // 50%
    uint256 public constant DEV_SHARE_BPS = 4000; // 40% to human dev
    uint256 public constant RETAINED_BPS = 1000; // 10% stays in contract for next round
    // Edge: 1 = top, 2 = right, 3 = bottom, 4 = left
    uint256 public constant EDGE_TOP = 1;
    uint256 public constant EDGE_RIGHT = 2;
    uint256 public constant EDGE_BOTTOM = 3;
    uint256 public constant EDGE_LEFT = 4;

    uint256 public minX; // playable bounds [minX, maxX] x [minY, maxY]
    uint256 public maxX;
    uint256 public minY;
    uint256 public maxY;
    uint256 public lastAdvanceAt;
    uint256 public gameId;

    // gameId => (x,y) => agent address (0 = empty). No two agents on same cell.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => address))) public positionToAgent;
    // gameId => agent => (x, y). One position per agent per game.
    mapping(uint256 => mapping(address => uint256)) public agentX;
    mapping(uint256 => mapping(address => uint256)) public agentY;
    mapping(uint256 => mapping(address => bool)) public hasPosition;

    uint256 public ethPool;
    uint256 public tokenPool;

    address public devAddress; // 40% of resolution goes here

    event Entered(uint256 indexed gameId, address indexed agent, uint256 x, uint256 y);
    event Moved(uint256 indexed gameId, address indexed agent, uint256 fromX, uint256 fromY, uint256 toX, uint256 toY);
    event RoundAdvanced(uint256 indexed gameId, uint256 edge); // 1=top, 2=right, 3=bottom, 4=left
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 ethWon, uint256 tokenWon);
    event Rollover(uint256 indexed gameId, uint256 ethPool, uint256 tokenPool);
    event DevAddressUpdated(address indexed previousDev, address indexed newDev);

    constructor(address _token, address _devAddress) Ownable(msg.sender) {
        token = ClawstrophobiaToken(_token);
        devAddress = _devAddress != address(0) ? _devAddress : msg.sender;
        lastAdvanceAt = block.timestamp;
        gameId = 1;
        minX = 0;
        maxX = GRID_SIZE - 1;
        minY = 0;
        maxY = GRID_SIZE - 1;
    }

    function setDevAddress(address _devAddress) external onlyOwner {
        address prev = devAddress;
        devAddress = _devAddress;
        emit DevAddressUpdated(prev, _devAddress);
    }

    function enter(uint256 x, uint256 y) external nonReentrant {
        require(x < GRID_SIZE && y < GRID_SIZE, "out of grid");
        require(_isPlayable(x, y), "cell not playable");
        require(positionToAgent[gameId][x][y] == address(0), "cell occupied");
        require(!hasPosition[gameId][msg.sender], "already on board");

        token.transferFrom(msg.sender, address(this), ENTRY_COST);
        tokenPool += ENTRY_COST;

        positionToAgent[gameId][x][y] = msg.sender;
        agentX[gameId][msg.sender] = x;
        agentY[gameId][msg.sender] = y;
        hasPosition[gameId][msg.sender] = true;

        emit Entered(gameId, msg.sender, x, y);
    }

    function move(uint256 toX, uint256 toY) external payable nonReentrant {
        require(msg.value == MOVE_COST, "need 0.001 ETH");
        require(hasPosition[gameId][msg.sender], "not on board");
        require(toX < GRID_SIZE && toY < GRID_SIZE, "out of grid");
        require(_isPlayable(toX, toY), "cell not playable");
        require(positionToAgent[gameId][toX][toY] == address(0), "cell occupied");

        ethPool += msg.value;

        uint256 fromX = agentX[gameId][msg.sender];
        uint256 fromY = agentY[gameId][msg.sender];

        positionToAgent[gameId][fromX][fromY] = address(0);
        positionToAgent[gameId][toX][toY] = msg.sender;
        agentX[gameId][msg.sender] = toX;
        agentY[gameId][msg.sender] = toY;

        emit Moved(gameId, msg.sender, fromX, fromY, toX, toY);
    }

    function advanceRound() external nonReentrant {
        require(block.timestamp >= lastAdvanceAt + ROUND_DURATION, "too soon");

        lastAdvanceAt = block.timestamp;

        if (minX == maxX && minY == maxY) {
            // Resolve game: 50% winner, 40% dev, 10% retained in contract. On rollover, winner share stays in pool.
            address winner = positionToAgent[gameId][minX][minY];
            uint256 ethWinner = (ethPool * WINNER_SHARE_BPS) / 10_000;
            uint256 ethDev = (ethPool * DEV_SHARE_BPS) / 10_000;
            uint256 tokenWinner = (tokenPool * WINNER_SHARE_BPS) / 10_000;
            uint256 tokenDev = (tokenPool * DEV_SHARE_BPS) / 10_000;

            ethPool -= ethDev;
            tokenPool -= tokenDev;
            if (winner != address(0)) {
                ethPool -= ethWinner;
                tokenPool -= tokenWinner;
                (bool okWinner,) = payable(winner).call{value: ethWinner}("");
                require(okWinner, "ETH transfer to winner failed");
                token.transfer(winner, tokenWinner);
                emit GameResolved(gameId, winner, ethWinner, tokenWinner);
            } else {
                emit Rollover(gameId, ethPool, tokenPool);
            }
            (bool okDev,) = payable(devAddress).call{value: ethDev}("");
            require(okDev, "ETH transfer to dev failed");
            token.transfer(devAddress, tokenDev);

            gameId++;
            minX = 0;
            maxX = GRID_SIZE - 1;
            minY = 0;
            maxY = GRID_SIZE - 1;
            return;
        }

        // Only remove an edge that still has room (so we eventually reach 1x1).
        // Top/bottom only if more than one row; left/right only if more than one column.
        uint256[4] memory valid;
        uint256 count = 0;
        if (minY < maxY) {
            valid[count++] = EDGE_TOP;
            valid[count++] = EDGE_BOTTOM;
        }
        if (minX < maxX) {
            valid[count++] = EDGE_RIGHT;
            valid[count++] = EDGE_LEFT;
        }
        require(count > 0, "no edge to remove");
        uint256 r = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, gameId))) % count;
        uint256 edge = valid[r];

        if (edge == EDGE_TOP) {
            minY++;
        } else if (edge == EDGE_RIGHT) {
            maxX--;
        } else if (edge == EDGE_BOTTOM) {
            maxY--;
        } else {
            minX++;
        }

        emit RoundAdvanced(gameId, edge);
    }

    function _isPlayable(uint256 x, uint256 y) internal view returns (bool) {
        return x >= minX && x <= maxX && y >= minY && y <= maxY;
    }

    function isPlayable(uint256 x, uint256 y) external view returns (bool) {
        return x < GRID_SIZE && y < GRID_SIZE && _isPlayable(x, y);
    }

    /// @dev Cells on the current boundary (any edge might be removed next round).
    function isDanger(uint256 x, uint256 y) external view returns (bool) {
        if ((minX == maxX && minY == maxY) || !_isPlayable(x, y)) return false;
        return x == minX || x == maxX || y == minY || y == maxY;
    }

    function getAgentAt(uint256 x, uint256 y) external view returns (address) {
        return positionToAgent[gameId][x][y];
    }

    function getAgentPosition(address agent) external view returns (uint256 x, uint256 y, bool onBoard) {
        onBoard = hasPosition[gameId][agent];
        x = agentX[gameId][agent];
        y = agentY[gameId][agent];
    }

    function getPlayableBounds()
        external
        view
        returns (uint256 _minX, uint256 _maxX, uint256 _minY, uint256 _maxY)
    {
        return (minX, maxX, minY, maxY);
    }

    function getGameState()
        external
        view
        returns (
            uint256 _gameId,
            uint256 _minX,
            uint256 _maxX,
            uint256 _minY,
            uint256 _maxY,
            uint256 _lastAdvanceAt,
            uint256 _ethPool,
            uint256 _tokenPool,
            uint256 nextAdvanceAt
        )
    {
        return (
            gameId,
            minX,
            maxX,
            minY,
            maxY,
            lastAdvanceAt,
            ethPool,
            tokenPool,
            lastAdvanceAt + ROUND_DURATION
        );
    }

    receive() external payable {
        ethPool += msg.value;
    }
}
