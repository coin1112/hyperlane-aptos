// These chains may be any protocol type.
// Placing them here instead of adjacent chains file to avoid circular dep
export const mainnet3SupportedChainNames = [
  'ancient8',
  'arbitrum',
  'avalanche',
  'base',
  'blast',
  'bob',
  'bsc',
  'celo',
  'cheesechain',
  'cyber',
  'degenchain',
  'eclipse',
  'endurance',
  'ethereum',
  'fraxtal',
  'fusemainnet',
  'gnosis',
  'immutablezkevm',
  'inevm',
  'injective',
  'kinto',
  'kroma',
  'linea',
  'lisk',
  'lukso',
  'mantapacific',
  'mantle',
  'merlin',
  'metis',
  'mint',
  'mode',
  'moonbeam',
  'neutron',
  'optimism',
  'osmosis',
  'polygon',
  'polygonzkevm',
  'proofofplay',
  'real',
  'redstone',
  'sanko',
  'scroll',
  'sei',
  'solana',
  'taiko',
  'tangle',
  'viction',
  'worldchain',
  'xai',
  'xlayer',
  'zetachain',
  'zircuit',
  'zoramainnet',
] as const;

export const supportedChainNames = [...mainnet3SupportedChainNames];
