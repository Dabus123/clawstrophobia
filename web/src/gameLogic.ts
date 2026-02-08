const GRID_SIZE = 100;

export function isPlayable(
  x: number,
  y: number,
  minX: number,
  maxX: number,
  minY: number,
  maxY: number
): boolean {
  if (x >= GRID_SIZE || y >= GRID_SIZE) return false;
  return x >= minX && x <= maxX && y >= minY && y <= maxY;
}

/** Cells on the boundary (any of the four edges might be removed next round). */
export function isDanger(
  x: number,
  y: number,
  minX: number,
  maxX: number,
  minY: number,
  maxY: number
): boolean {
  if (!isPlayable(x, y, minX, maxX, minY, maxY)) return false;
  if (minX === maxX && minY === maxY) return false; // single cell left
  return x === minX || x === maxX || y === minY || y === maxY;
}
