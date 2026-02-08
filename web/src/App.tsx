import { useState, useEffect, useCallback } from 'react';
import { createPublicClient, http, type Address } from 'viem';
import { base } from 'viem/chains';
import { gameAbi } from './abis';
import { isPlayable as isPlayableCell, isDanger as isDangerCell } from './gameLogic';

const GAME_ADDRESS = (import.meta.env.VITE_GAME_ADDRESS || '') as Address;
const CHAIN = base;

const publicClient = createPublicClient({
  chain: CHAIN,
  transport: http(),
});

export type GameState = {
  gameId: bigint;
  minX: bigint;
  maxX: bigint;
  minY: bigint;
  maxY: bigint;
  lastAdvanceAt: bigint;
  ethPool: bigint;
  tokenPool: bigint;
  nextAdvanceAt: bigint;
};

function useGameState() {
  const [state, setState] = useState<GameState | null>(null);
  const [grid, setGrid] = useState<Record<string, Address>>({});
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    if (!GAME_ADDRESS) {
      setLoading(false);
      return;
    }
    try {
      const s = await publicClient.readContract({
        address: GAME_ADDRESS,
        abi: gameAbi,
        functionName: 'getGameState',
      });
      const [gameId, minX, maxX, minY, maxY, lastAdvanceAt, ethPool, tokenPool, nextAdvanceAt] = s;
      setState({
        gameId,
        minX,
        maxX,
        minY,
        maxY,
        lastAdvanceAt,
        ethPool,
        tokenPool,
        nextAdvanceAt,
      });
      const CHUNK = 500;
      const calls = Array.from({ length: 100 * 100 }, (_, i) => ({
        address: GAME_ADDRESS,
        abi: gameAbi,
        functionName: 'getAgentAt' as const,
        args: [BigInt(i % 100), BigInt(Math.floor(i / 100))] as const,
      }));
      const next: Record<string, Address> = {};
      for (let offset = 0; offset < calls.length; offset += CHUNK) {
        const chunk = calls.slice(offset, offset + CHUNK);
        const results = await publicClient.multicall({
          contracts: chunk,
          allowFailure: false,
        });
        results.forEach((agent, i) => {
          if (agent && agent !== '0x0000000000000000000000000000000000000000') {
            const idx = offset + i;
            next[`${idx % 100},${Math.floor(idx / 100)}`] = agent;
          }
        });
      }
      setGrid(next);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 15000);
    return () => clearInterval(interval);
  }, [refresh]);

  return { state, grid, loading, refresh };
}

function Cell({
  x,
  y,
  gameState,
  agent,
}: {
  x: number;
  y: number;
  gameState: GameState | null;
  agent: Address | undefined;
}) {
  if (!gameState) {
    return <div className="cell outside" />;
  }
  const minX = Number(gameState.minX);
  const maxX = Number(gameState.maxX);
  const minY = Number(gameState.minY);
  const maxY = Number(gameState.maxY);
  const playable = isPlayableCell(x, y, minX, maxX, minY, maxY);
  const danger = isDangerCell(x, y, minX, maxX, minY, maxY);
  const classes = [
    'cell',
    playable ? 'playable' : 'outside',
    danger ? 'danger' : '',
    agent ? 'agent' : '',
  ].filter(Boolean);
  return (
    <div
      className={classes.join(' ')}
      title={agent ? `Agent: ${agent.slice(0, 8)}...` : playable ? `(${x},${y})` : undefined}
    />
  );
}

function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function formatEth(wei: bigint) {
  return (Number(wei) / 1e18).toFixed(4);
}

function App() {
  const { state, grid, loading, refresh } = useGameState();

  const secondsUntilNext = state
    ? Math.max(0, Number(state.nextAdvanceAt) - Math.floor(Date.now() / 1000))
    : 0;

  if (!GAME_ADDRESS) {
    return (
      <div className="grid-wrap">
        <h1>Clawstrophobia</h1>
        <p>Set VITE_GAME_ADDRESS in .env to view contract state.</p>
      </div>
    );
  }

  return (
    <div className="grid-wrap">
      <header className="header">
        <h1>Clawstrophobia</h1>
        <a href="/simulation/" target="_blank" rel="noopener noreferrer" style={{ fontSize: '0.875rem', color: '#9ca3af' }}>
          Simulation
        </a>
      </header>

      {state && (
        <div className="stats">
          <span>Game <strong>#{state.gameId.toString()}</strong></span>
          <span>Bounds <strong>{state.minX.toString()}-{state.maxX.toString()} × {state.minY.toString()}-{state.maxY.toString()}</strong></span>
          <span>Next edge <strong>{formatTime(secondsUntilNext)}</strong></span>
          <span>ETH pool <strong>{formatEth(state.ethPool)}</strong></span>
          <span>$CLAWSTROPHOBIA pool <strong>{(Number(state.tokenPool) / 1e18).toFixed(0)}</strong></span>
          <button type="button" className="btn btn-secondary" onClick={refresh} disabled={loading}>
            Refresh
          </button>
        </div>
      )}

      <div className="legend">
        <div className="legend-item"><span className="legend-swatch danger" /> Danger (blinks) — move or risk elimination</div>
        <div className="legend-item"><span className="legend-swatch playable" /> Playable</div>
        <div className="legend-item"><span className="legend-swatch agent" /> Agent</div>
        <div className="legend-item"><span className="legend-swatch outside" /> Outside (eliminated)</div>
      </div>

      {loading ? (
        <p>Loading grid…</p>
      ) : (
        <div className="grid">
          {Array.from({ length: 100 * 100 }, (_, i) => {
            const x = i % 100;
            const y = Math.floor(i / 100);
            return (
              <Cell
                key={`${x}-${y}`}
                x={x}
                y={y}
                gameState={state}
                agent={grid[`${x},${y}`]}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

export default App;
