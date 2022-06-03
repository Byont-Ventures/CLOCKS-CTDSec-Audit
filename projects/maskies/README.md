# Maskies
## Custom source files
- `src/Maskies.sol`
- `lib/Whitelisting/src/Whitelist.sol`

The import versions used are:
- `ERC721Psi`: 0.6.0
- `@openzeppelin/contracts`: 4.6.0

## Custom test files
- `test/utils/util.sol`
- `test/Maskies.t.sol`

A test report with the output of testing with forge (and it's fuzz tester) and slither can be found at `test/testReport.md`. This file also shown the tool versions used. For slither's printer documentation see [this](https://github.com/crytic/slither/wiki/Printer-documentation). For slither's detector documentation see [this](https://github.com/crytic/slither/wiki/Detector-Documentation).


More detailed slither output can be found in `test/slither/slither-human-summary-output.json`. To see which detectors of slither found something where in the code search for `"check": "` in this json file. 

Note that you will see that Slither (thinks) it found a reentrancy in the withdrawal functions. However, we use openzeppelin's `nonReentrant` modifier on these functions.

## Flat source
- `_flat/Maskies.sol`

This file was created using the [sol-merger](https://yarnpkg.com/?q=sol-merger&p=1) package v4.1.1 and the --remove-comments flag