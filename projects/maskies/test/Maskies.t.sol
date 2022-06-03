pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./utils/util.sol";
import "./murky/Merkle.sol";

import "src/Maskies.sol";

// https://soliditydeveloper.com/foundry

contract test_Maskies is Test {
    using Address for address; // To use isContract()

    // Events from the Maskies contract
    event Mint(address minter, uint256 amount, bytes32[] proof);
    event MintReserved(uint256 amount, address to);
    event SetMaxTotalMintsThisStage(uint256 newMax);
    event FlipWhitelistState(bool newState);
    event SetMaxMintBatchAmount(uint256 newLimit);
    event SetPricePerToken(uint256 newPricePerToken);
    event MerkleRootSet(bytes32 newMerkeRoot);
    event SetBaseURI();
    event SetUnrevealedURI(string newUnrevealedURI);
    event FlipReleaved(bool newState);
    event WithdrawAmount(uint256 amount);
    event WithdrawAll(uint256 amount);
    event ChangeOwner(address newOwner);

    Utils internal utils;
    Merkle internal m;
    Maskies nftContract;

    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal carol;

    fallback() external payable { }
    receive() external payable { }

    function setUp() public {
        nftContract = new Maskies();

        utils = new Utils(vm);
        m = new Merkle();

        users = utils.createUsers(5);

        alice = users[0];
        vm.label(alice, "Alice");

        bob = users[1];
        vm.label(bob, "Bob");

        carol = users[2];
        vm.label(carol, "Carol");
    }   

    //--------------------------------------------------
    // ERC721Psi related
    //--------------------------------------------------
    function testNameAndSymbolAreCorrect() public {
        assertEq(nftContract.name(), "Maskies");
        assertEq(nftContract.symbol(), "MSK");
    }

    //-------------------------
    // Minting related
    //-------------------------
    function testCanMint(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount, uint256 amount) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(amount <= maxMints);
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));
        vm.assume(ethAmount >= nftContract.pricePerToken() * amount);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        bytes32 root = m.getRoot(usedData);
        nftContract.setMerkleRoot(root);
        assertEq(nftContract.merkleRoot(), root);

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);

        assertEq(nftContract.balanceOf(leaf), amount);
        assertEq(nftContract.totalSupply(), amount);
    }

    function testCannotMintZeroAmount(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(leaf != address(0));

        assertTrue(nftContract.whitelistIsActive());

        uint256 amount = 0;

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        bytes32 root = m.getRoot(usedData);
        nftContract.setMerkleRoot(root);
        assertEq(nftContract.merkleRoot(), root);

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        vm.prank(leaf);

        vm.expectRevert(bytes('ERC721Psi: quantity must be greater 0'));
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);
    }

    function testCannnotMintMoreThenMaxBatchAmount(uint256 amount, bytes32[] memory proof) public {
        vm.assume(amount <= nftContract.maxTotalMintsThisStage());

        // The thing to test
        vm.assume(amount > nftContract.maxMintBatchAmount());

        vm.expectRevert(bytes('Maximum batch size reached'));
        nftContract.mint(address(1), 1, amount, proof);
    }

    function testCannotMintWithInsufficientEth(uint256 ethAmount, uint256 maxMints, uint256 amount, bytes32[] memory proof) public {
        // To pass the requires
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));

        // Give the address ethAmount of ehter (in the smallest unit)
        address ownerAddress = nftContract.owner();
        vm.deal(ownerAddress, ethAmount);

        // The thing to test
        vm.assume(ethAmount < nftContract.pricePerToken() * amount);

        vm.expectRevert(bytes('Not enough ETH for transaction'));
        nftContract.mint{value: ethAmount}(ownerAddress, maxMints, amount, proof);
    }

    function testCannotMintWithInvalidProof(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount, uint256 amount) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));
        vm.assume(ethAmount >= nftContract.pricePerToken() * amount);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // The thing to test
        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 invalidDataIndexModifier = 0;
        bytes32[] memory invalidData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                invalidDataIndexModifier = 1;
                invalidData[i] = leafBytes32;
            } else {
                vm.assume(data[i - invalidDataIndexModifier] != 0);
                invalidData[i] = data[i - invalidDataIndexModifier];
            }
        }

        bytes32 validRoot = m.getRoot(data);
        nftContract.setMerkleRoot(validRoot);
        assertEq(nftContract.merkleRoot(), validRoot);

        bytes32[] memory invalidProof = m.getProof(invalidData, indexOfLeaf);

        // Make the non-whitelisted address call the contract
        vm.prank(leaf);

        vm.expectRevert(bytes('Address not whitelisted'));
        // The smart contract has the root of the merkle tree of 'data'
        // But a proof is given for leaf to be included in 'invalidProof'.
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, invalidProof);
    }

    function testUserCannotMintMoreThenPerUserLimit(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 maxBatch) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(maxBatch > 0);
        vm.assume(maxBatch <= nftContract.maxTotalMintsThisStage());
        vm.assume(maxMints <= nftContract.maxTotalMintsThisStage() - maxBatch);
        vm.assume(maxMints > 0);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        bytes32 root = m.getRoot(usedData);
        nftContract.setMerkleRoot(root);
        assertEq(nftContract.merkleRoot(), root);

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        nftContract.setMaxMintBatchAmount(maxBatch);

        uint256 roundsShouldBeSuccesful = maxMints/maxBatch;
        uint256 ethAmount = maxBatch * nftContract.pricePerToken();

        for(uint256 r = 0; r < roundsShouldBeSuccesful; r++) { 
            vm.deal(leaf, ethAmount);
            vm.prank(leaf);
            nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
            assertEq(nftContract.balanceOf(leaf), (r+1)*maxBatch);
        }

        vm.expectRevert(bytes('Address would exceed balance limit'));
        vm.deal(leaf, ethAmount);
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
    }

    function testCannotMintMoreThanMaxTotalMintsThisStage(address leaf) public {
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        uint256 maxMints = nftContract.maxTotalMintsThisStage() + 1;

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 maxBatch = nftContract.maxMintBatchAmount();

        uint256 roundsShouldBeSuccesful = nftContract.maxTotalMintsThisStage()/maxBatch;
        uint256 ethAmount = maxBatch * nftContract.pricePerToken();

        for(uint256 r = 0; r < roundsShouldBeSuccesful; r++) { 
            vm.deal(leaf, ethAmount);
            vm.prank(leaf);
            nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
            assertEq(nftContract.balanceOf(leaf), (r+1)*maxBatch);
        }

        vm.expectRevert(bytes('Would reach max mints in this stage'));
        vm.deal(leaf, ethAmount);
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
    }

    function testGivingOtherMaxMintsDoesNotFoolMerkleProof(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount, uint256 amount) public {
         // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(maxMints < type(uint256).max); // So that I can do maxMints+1 later without getting "Arithmetic over/underflow"
        vm.assume(maxMints > 0); 
        vm.assume(amount <= maxMints);
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));
        vm.assume(ethAmount >= nftContract.pricePerToken() * amount);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        bytes32 root = m.getRoot(usedData);
        nftContract.setMerkleRoot(root);
        assertEq(nftContract.merkleRoot(), root);

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        vm.expectRevert(bytes('Address not whitelisted'));
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints + 1, amount, proof);
    }

    function testCannotMintMoreThanTotalMintsMinusTotalReservedMints(address leaf, uint16 _mintingAmount) public {
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());
        vm.assume(_mintingAmount > 0);
        uint256 mintingAmount = _mintingAmount + (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT());
        vm.assume(mintingAmount <= nftContract.MAX_TOKENS());

        assertTrue(nftContract.whitelistIsActive());

        nftContract.setMaxTotalMintsThisStage(nftContract.MAX_TOKENS());
        assertEq(nftContract.maxTotalMintsThisStage(), nftContract.MAX_TOKENS());

        uint256 maxMints = mintingAmount;

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 maxBatch = nftContract.maxMintBatchAmount();

        uint256 roundsShouldBeSuccesful = (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT())/maxBatch;
        uint256 ethAmount = maxBatch * nftContract.pricePerToken();

        for(uint256 r = 0; r < roundsShouldBeSuccesful; r++) {
            vm.deal(leaf, ethAmount);
            vm.prank(leaf);
            nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
            assertEq(nftContract.balanceOf(leaf), (r+1)*maxBatch);
        }

        vm.expectRevert(bytes('Would reach maximum supply'));
        vm.deal(leaf, ethAmount);
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
    }

    function testCannotMintMoreThanTotalMintsMinusReservedMints(address leaf, uint256 reservedMints, uint16 _mintingAmount) public {
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());
        vm.assume(reservedMints > 1);
        vm.assume(reservedMints <= nftContract.RESERVED_AMOUNT());
        
        uint256 maxBatch = nftContract.maxMintBatchAmount();

        vm.assume(_mintingAmount > 0);
        uint256 mintingAmount = _mintingAmount + (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT());
        vm.assume(mintingAmount <= nftContract.MAX_TOKENS()); 
        vm.assume((reservedMints + mintingAmount + maxBatch) < nftContract.MAX_TOKENS()); // To avoid 'Would reach max mints in this stage'

        assertTrue(nftContract.whitelistIsActive());

        nftContract.setMaxTotalMintsThisStage(nftContract.MAX_TOKENS());
        assertEq(nftContract.maxTotalMintsThisStage(), nftContract.MAX_TOKENS());

        // Mint some reserved NFTs to alice
        nftContract.mintReserved(reservedMints, alice);

        uint256 maxMints = mintingAmount;

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 roundsShouldBeSuccesful = (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT())/maxBatch;
        uint256 ethAmount = maxBatch * nftContract.pricePerToken();

        for(uint256 r = 0; r < roundsShouldBeSuccesful; r++) { 
            vm.deal(leaf, ethAmount);
            vm.prank(leaf);
            nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
            assertEq(nftContract.balanceOf(leaf), (r+1)*maxBatch);
        }

        vm.expectRevert(bytes('Would reach maximum supply'));
        vm.deal(leaf, ethAmount);
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, maxBatch, proof);
    }

    //-------------------------
    // Minting reserved related
    //-------------------------
    function testCanMintReservedNft(uint256 amount, address to) public {
        // Ignore the precompiled contracts: https://blog.qtum.org/precompiled-contracts-and-confidential-assets-55f2b47b231d
        vm.assume(uint160(to) > 8);
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.RESERVED_AMOUNT());
        vm.assume(!to.isContract());

        // Check initial balance
        assertEq(nftContract.reservedTokensMinted(), 0);
        
        uint256 initialBalanceTo = nftContract.balanceOf(to);
        
        assertEq(initialBalanceTo, 0);

        // Mint NFT(s) and check the new balance
        uint256 expectedBalanceTo = initialBalanceTo + amount;

        nftContract.mintReserved(amount, to);
        uint256 newBalanceTo = nftContract.balanceOf(to);

        assertEq(newBalanceTo, expectedBalanceTo);
        assertEq(nftContract.reservedTokensMinted(), amount);
    }

    function testMintReservedRevertsOnZeroAmount(address to) public {
        vm.assume(to != address(0));
        vm.expectRevert(bytes("ERC721Psi: quantity must be greater 0"));

        nftContract.mintReserved(0, to);
    }

    function testMintReservedRevertsOnZeroAddress(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.RESERVED_AMOUNT());
        vm.expectRevert(bytes("ERC721Psi: mint to the zero address"));

        nftContract.mintReserved(amount, address(0));
    }

    function testMintReservedCanNotMintMoreThenReservedAmount(uint256 amount, address to) public {
        vm.assume(to != address(0));
        vm.assume(amount > nftContract.RESERVED_AMOUNT());
        vm.expectRevert(bytes("Would be more than reserved amount"));

        nftContract.mintReserved(amount, to);
    }

    //-------------------------
    // Transfer related
    //-------------------------
    function testCanTransferNft(address receiver, uint256 tokenId, address leaf, uint256 maxMints, uint256 amount) public {
        // To pass the requires
        vm.assume(tokenId < amount);
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(leaf != receiver);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());
        vm.assume(maxMints > 0);
        vm.assume(receiver != address(0));
        vm.assume(!receiver.isContract());

        assertTrue(nftContract.whitelistIsActive());

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 ethAmount = nftContract.pricePerToken() * amount;
        vm.deal(leaf, ethAmount);

        // Mint a certain batch
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);

        // Transfer tokenId to from leaf to receiver
        uint256 initalFromBalance = nftContract.balanceOf(leaf);
        uint256 initalToBalance = nftContract.balanceOf(receiver);

        assertEq(nftContract.ownerOf(tokenId), leaf);

        vm.prank(leaf);
        nftContract.transferFrom(leaf, receiver, tokenId);

        assertEq(nftContract.balanceOf(leaf), initalFromBalance - 1);
        assertEq(nftContract.balanceOf(receiver), initalToBalance + 1);

        assertEq(nftContract.ownerOf(tokenId), receiver);
    }

    function testCannotTransferNonOwnedNft(address receiver, uint256 tokenId, address leaf, uint256 maxMints, uint256 amount) public {
        // To pass the requires
        vm.assume(tokenId < amount);
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(leaf != receiver);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());
        vm.assume(maxMints > 0);
        vm.assume(receiver != address(0));
        vm.assume(!receiver.isContract());

        assertTrue(nftContract.whitelistIsActive());

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 ethAmount = nftContract.pricePerToken() * amount;
        vm.deal(leaf, ethAmount);

        // Mint a certain batch
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);

        assertEq(nftContract.ownerOf(tokenId), leaf);

        // The receier should not be able to transfer a NFT which it
        // doesn't own
        vm.expectRevert(bytes('ERC721Psi: transfer caller is not owner nor approved'));
        vm.prank(receiver);
        nftContract.transferFrom(leaf, receiver, tokenId);
    }
    //--------------------------------------------------
    // Sale settings related
    //--------------------------------------------------
    function testCanSetMaxTotalMintsThisStage(uint256 newMax) public {
        vm.assume(newMax <= nftContract.MAX_TOKENS());

        nftContract.setMaxTotalMintsThisStage(newMax);
        uint256 newMaxTotalMintsThisStage = nftContract.maxTotalMintsThisStage();

        assertEq(newMaxTotalMintsThisStage, newMax);
    }

    function testCannotSetMaxTotalMintsThisStageHigherThanTotalMax(uint256 newMax) public {
        vm.assume(newMax > nftContract.MAX_TOKENS());

        vm.expectRevert(bytes('Stage max cannot exceed MAX_TOKENS'));
        nftContract.setMaxTotalMintsThisStage(newMax);
    }

    function testCanFlipWhitelistState() public {
        bool initialWhitelistIsActive = nftContract.whitelistIsActive();
        nftContract.flipWhitelistState();
        bool newWhitelistIsActive = nftContract.whitelistIsActive();

        assertEq(newWhitelistIsActive, !initialWhitelistIsActive);
    }

    function testCannotSetMintBatchAmountHigherThanTotalMax(uint256 newMax) public {
        vm.assume(newMax > nftContract.MAX_TOKENS());

        vm.expectRevert(bytes('Batch max cannot exceed MAX_TOKENS'));
        nftContract.setMaxMintBatchAmount(newMax);
    }

    function testCanSetMaxMintBatchAmount(uint256 newMax) public {
        vm.assume(newMax <= nftContract.MAX_TOKENS());

        nftContract.setMaxMintBatchAmount(newMax);
        uint256 newMaxMintBatchAmount = nftContract.maxMintBatchAmount();

        assertEq(newMaxMintBatchAmount, newMax);
    }

    function testCanSetPricePerToken(uint256 newPrice) public {
        nftContract.setPricePerToken(newPrice);
        uint256 newPricePerToken = nftContract.pricePerToken();

        assertEq(newPricePerToken, newPrice);
    }

    //--------------------------------------------------
    // Merkle proof related
    //--------------------------------------------------
    function testCanSetMerkleRoot(bytes32 newRoot) public {
        vm.assume(newRoot != keccak256(abi.encode(uint256(0))));

        nftContract.setMerkleRoot(newRoot);
        bytes32 newMerkleRoot = nftContract.merkleRoot();

        assertEq(newMerkleRoot, newRoot);
    }

    function testRevertsOnZeroRoot() public {
        vm.expectRevert(bytes('Merkle root cannot be 0'));
        nftContract.setMerkleRoot(keccak256(abi.encode(uint256(0))));
    }

    function testRevertsWhenNoMerkleRootIsSet(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount, uint256 amount) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(amount <= maxMints);
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));
        vm.assume(ethAmount >= nftContract.pricePerToken() * amount);

        assertTrue(nftContract.whitelistIsActive());

        vm.assume(leaf != address(0));

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        // Don't set a root

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        vm.expectRevert(bytes('Merkle root not set'));
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);
    }

    //--------------------------------------------------
    // URI related
    //--------------------------------------------------
    function testCannotSetEmptyBaseURI() public {
        vm.expectRevert(bytes('URI cannot be empty'));

        string memory newURI = '';
        nftContract.setBaseURI(newURI);
    }

    function testCannotSetEmptyUnrevealedURI() public {
        vm.expectRevert(bytes('URI cannot be empty'));

        string memory newURI = '';
        nftContract.setUnrevealedURI(newURI);
    }


    function testCanSetBaseURI(string memory newURI) public {
        vm.assume(bytes(newURI).length > 0);

        nftContract.setBaseURI(newURI);
        string memory newBaseTokenURI = nftContract.baseTokenURI();

        assertEq(newBaseTokenURI, newURI);
    }

    function testCanSetUnrevealedURI(string memory newURI) public {
        vm.assume(bytes(newURI).length > 0);

        nftContract.setUnrevealedURI(newURI);
        string memory newUnrevealedURI = nftContract.unrevealedURI();

        assertEq(newUnrevealedURI, newURI);
    }

    function testCanFlipReleaved() public {
        bool initialRevealed = nftContract.revealed();
        nftContract.flipReleaved();
        bool newRevealed = nftContract.revealed();

        assertEq(newRevealed, !initialRevealed);
    }

    function testRevertsOnNonExistingTokenId(uint256 tokenId) public {
        vm.expectRevert(bytes('URI query for nonexistent token'));
        nftContract.tokenURI(tokenId);
    }

    function testReturnUnrevealedUriWhenNotRevealed(string memory unreleavedUri, uint256 tokenId, address leaf, uint256 maxMints, uint256 amount) public {
        // To pass the requires
        vm.assume(bytes(unreleavedUri).length > 0);
        vm.assume(tokenId < amount);
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(maxMints > 0);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 ethAmount = nftContract.pricePerToken() * amount;
        vm.deal(leaf, ethAmount);

        nftContract.setUnrevealedURI(unreleavedUri);

        // Mint a certain batch
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);
        assertEq(nftContract.balanceOf(leaf), amount);
        assertEq(nftContract.totalSupply(), amount);

        string memory receivedUri = nftContract.tokenURI(tokenId);
        assertEq(receivedUri, unreleavedUri);
    }

    function testReturnRevealedUriWhenRevealed(string memory releavedUri, uint256 tokenId, address leaf, uint256 maxMints, uint256 amount) public {
        // To pass the requires
        vm.assume(bytes(releavedUri).length > 0);
        vm.assume(tokenId < amount);
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(maxMints > 0);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());

        assertTrue(nftContract.whitelistIsActive());

        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, 1));
        data[1] = keccak256(abi.encode(bob, 1));
        data[2] = keccak256(abi.encode(leaf, maxMints));
        data[3] = keccak256(abi.encode(carol, 1));

        nftContract.setMerkleRoot(m.getRoot(data));
        bytes32[] memory proof = m.getProof(data, 2);

        uint256 ethAmount = nftContract.pricePerToken() * amount;
        vm.deal(leaf, ethAmount);

        nftContract.setBaseURI(releavedUri);

        // Mint a certain batch
        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);
        assertEq(nftContract.balanceOf(leaf), amount);
        assertEq(nftContract.totalSupply(), amount);
        
        // Reveal the NFT
        nftContract.flipReleaved();

        string memory expectedUri = string(abi.encodePacked(releavedUri, Strings.toString(tokenId), ".json"));
        string memory receivedUri = nftContract.tokenURI(tokenId);
        assertEq(receivedUri, expectedUri);
    }

    //--------------------------------------------------
    // Withdrawel related
    //--------------------------------------------------
    function testCannotWithdrawMoreThanContractBalance(uint256 contractBalance, uint256 withdrawAmount) public {
        vm.assume(withdrawAmount > contractBalance);
        
        vm.deal(address(nftContract), contractBalance);

        vm.expectRevert(bytes('Not enough balance in contract'));
        nftContract.withdrawAmount(withdrawAmount);
    }

    function testCannotWithZeroAmount() public {
        vm.expectRevert(bytes('Amount should be greater than 0'));
        nftContract.withdrawAmount(0);
    }

    function testCannotWithWhenContractBalanceIsZero() public {
        vm.deal(address(nftContract), 0);

        vm.expectRevert(bytes('Contract balance is 0'));
        nftContract.withdrawAll();
    }

    function testCanWithdrawAmountFromContract(uint256 contractBalance, uint256 withdrawAmount) public {
        // Otherwise an error occures becuase it would overflow uint256
        vm.assume(contractBalance <= type(uint256).max - nftContract.owner().balance);
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= contractBalance);

        
        vm.deal(address(nftContract), contractBalance);

        uint256 initalOwnerBalance = nftContract.owner().balance;
        nftContract.withdrawAmount(withdrawAmount);
        uint256 newOwnerBalance = nftContract.owner().balance;
        uint256 newContractBalance = address(nftContract).balance;

        assertEq(newContractBalance, contractBalance - withdrawAmount);
        assertEq(newOwnerBalance, initalOwnerBalance + withdrawAmount);
    }

    function testCanWithdrawAllFromContract(uint256 contractBalance) public { 
        vm.assume(contractBalance <= type(uint256).max - nftContract.owner().balance);
        vm.assume(contractBalance > 0);

        vm.deal(address(nftContract), contractBalance);

        uint256 initalOwnerBalance = nftContract.owner().balance;
        nftContract.withdrawAll();
        uint256 newOwnerBalance = nftContract.owner().balance;
        uint256 newContractBalance = address(nftContract).balance;

        assertEq(newContractBalance, 0);
        assertEq(newOwnerBalance, initalOwnerBalance + contractBalance);
    }

    //--------------------------------------------------
    // Owner related
    //--------------------------------------------------
    function testCannotChangeOwnerToZeroAddress() public {
        vm.expectRevert(bytes('newOwner cannot be address(0)'));
        nftContract.changeOwner(address(0));
    }

    function testCannotChangeOwnerToCurrentOwner() public {
        address ownerAddress = nftContract.owner();

        vm.expectRevert(bytes('newowner cannot be current owner'));
        nftContract.changeOwner(ownerAddress);
    }

    function testCanChangeOwner(address newOwner, address attemptedNewOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != nftContract.owner());

        nftContract.changeOwner(newOwner);

        assertEq(nftContract.owner(), newOwner);

        vm.expectRevert(bytes('Ownable: caller is not the owner'));
        nftContract.changeOwner(attemptedNewOwner);
    }

    //--------------------------------------------------
    // onlyOwner related
    //--------------------------------------------------
    bytes constant onlyOwnerRevertString = bytes("Ownable: caller is not the owner");

    function testOnlyOwnerSetMaxTotalMintsThisStage(address payable caller, uint256 newMax) public {
        vm.assume(newMax < nftContract.MAX_TOKENS());
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.setMaxTotalMintsThisStage(newMax);
    }

    function testOnlyOwnerMintReserved(address payable caller, uint256 amount, address payable to) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.mintReserved(amount, to);
    }

    function testOnlyOwnerFlipWhitelistState(address payable caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.flipWhitelistState();
    }

    function testOnlyOwnerSetPricePerToken(address payable caller, uint256 newPricePerToken) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.setPricePerToken(newPricePerToken);
    }

    function testOnlyOwnerSetMerkleRoot(address payable caller, bytes32 newMerkleRoot) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.setMerkleRoot(newMerkleRoot);
    }

    function testOnlyOwnerSetBaseURI(address payable caller, string calldata newBaseURI) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.setBaseURI(newBaseURI);
    }

    function testOnlyOwnerSetUnrevealedURI(address payable caller, string calldata newUnrevealedURI) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.setUnrevealedURI(newUnrevealedURI);
    }

    function testOnlyOwnerFlipReleaved(address payable caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.flipReleaved();
    }

    function testOnlyOwnerWithDrawAmount(address payable caller, uint256 amount) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.withdrawAmount(amount);
    }

    function testOnlyOwnerWithDrawAll(address payable caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.withdrawAll();
    }

    function testOnlyOwnerChangeOwner(address payable caller, address newOwner) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.changeOwner(newOwner);
    }

    function testOnlyOwnerPauseContract(address payable caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.pauseContract();
    }

    function testOnlyOwnerUnpauseContract(address payable caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != nftContract.owner());
        vm.expectRevert(onlyOwnerRevertString);

        vm.prank(caller);
        nftContract.unpauseContract();
    }

    //--------------------------------------------------
    // emit related
    //--------------------------------------------------
    function testEmitMint(address leaf, uint256 maxMints, bytes32[] memory data, uint256 indexOfLeaf, uint256 ethAmount, uint256 amount) public {
        // To pass the requires
        vm.assume(data.length > 1);
        vm.assume(indexOfLeaf <= data.length);
        vm.assume(amount > 0);
        vm.assume(amount <= maxMints);
        vm.assume(amount <= nftContract.maxMintBatchAmount());
        vm.assume(amount <= (nftContract.MAX_TOKENS() - nftContract.RESERVED_AMOUNT()));
        vm.assume(ethAmount >= nftContract.pricePerToken() * amount);
        vm.assume(leaf != address(0));
        vm.assume(!leaf.isContract());
        vm.assume(maxMints > 0);
        
        assertTrue(nftContract.whitelistIsActive());

        // Give the address ethAmount of ehter (in the smallest unit) 
        vm.deal(leaf, ethAmount);

        bytes32 leafBytes32 = keccak256(abi.encode(leaf, maxMints));

        // Create a 'valid' tree of which the root is given to the smart contract
        uint256 usedDataIndexModifier = 0;
        bytes32[] memory usedData = new bytes32[](data.length + 1);
        for(uint256 i = 0; i <= data.length; i++) {
            if(i == indexOfLeaf) {
                usedDataIndexModifier = 1;
                usedData[i] = leafBytes32;
            } else {
                vm.assume(data[i - usedDataIndexModifier] != 0);
                usedData[i] = data[i - usedDataIndexModifier];
            }
        }

        bytes32 root = m.getRoot(usedData);
        nftContract.setMerkleRoot(root);

        bytes32[] memory proof = m.getProof(usedData, indexOfLeaf);

        vm.expectEmit(false, false, false, true);
        emit Mint(leaf, amount, proof);


        vm.prank(leaf);
        nftContract.mint{value: ethAmount}(leaf, maxMints, amount, proof);
    }

    function testEmitMintReserved(uint256 amount, address to) public {
        // Ignore the precompiled contracts: https://blog.qtum.org/precompiled-contracts-and-confidential-assets-55f2b47b231d
        vm.assume(uint160(to) > 8);
        vm.assume(!to.isContract());
        vm.assume(amount > 0);
        vm.assume(amount <= nftContract.RESERVED_AMOUNT());
        
        vm.expectEmit(false, false, false, true);
        emit MintReserved(amount, to);

        nftContract.mintReserved(amount, to);
    }

    function testEmitSetMaxTotalMintsThisStage(uint256 newMax) public {
        vm.assume(newMax <= nftContract.MAX_TOKENS());

        vm.expectEmit(false, false, false, true);
        emit SetMaxTotalMintsThisStage(newMax);

        nftContract.setMaxTotalMintsThisStage(newMax);
    }

    function testEmitFlipWhitelistState() public {
        bool initalState = nftContract.whitelistIsActive();
        
        vm.expectEmit(false, false, false, true);
        emit FlipWhitelistState(!initalState);

        nftContract.flipWhitelistState();
    }

    function testEmitSetMaxMintBatchAmount(uint256 newMax) public {
        vm.assume(newMax <= nftContract.MAX_TOKENS());

        vm.expectEmit(false, false, false, true);
        emit SetMaxMintBatchAmount(newMax);

        nftContract.setMaxMintBatchAmount(newMax);
    }

    function testEmitSetPricePerToken(uint256 newPricePerToken) public {
        vm.expectEmit(false, false, false, true);
        emit SetPricePerToken(newPricePerToken);

        nftContract.setPricePerToken(newPricePerToken);
    }

    function testEmitSetMerkleRoot(bytes32 newMerkleRoot) public {
        vm.assume(newMerkleRoot != 0);

        vm.expectEmit(false, false, false, true);
        emit MerkleRootSet(newMerkleRoot);

        nftContract.setMerkleRoot(newMerkleRoot);
    }

    function testEmitSetBaseURI(string calldata newBaseURI) public {
        vm.assume(bytes(newBaseURI).length > 0);
        
        vm.expectEmit(false, false, false, true);
        emit SetBaseURI();

        nftContract.setBaseURI(newBaseURI);
    }

    function testEmitSetUnrevealedURI(string calldata newUnrevealedURI) public {
        vm.assume(bytes(newUnrevealedURI).length > 0);

        vm.expectEmit(false, false, false, true);
        emit SetUnrevealedURI(newUnrevealedURI);

        nftContract.setUnrevealedURI(newUnrevealedURI);
    }

    function testEmitFlipReleaved() public {
        bool initalState = nftContract.revealed();
        
        vm.expectEmit(false, false, false, true);
        emit FlipReleaved(!initalState);

        nftContract.flipReleaved();
    }

    function testEmitWithdrawAmount(uint256 contractBalance, uint256 withdrawAmount) public {
        // Otherwise an error occures becuase it would overflow uint256
        vm.assume(contractBalance <= type(uint256).max - nftContract.owner().balance);
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= contractBalance);

        vm.deal(address(nftContract), contractBalance);

        vm.expectEmit(false, false, false, true);
        emit WithdrawAmount(withdrawAmount);

        nftContract.withdrawAmount(withdrawAmount);
    }

    function testEmitWithdrawAll(uint256 contractBalance) public { 
        vm.assume(contractBalance <= type(uint256).max - nftContract.owner().balance);
        vm.assume(contractBalance > 0);

        vm.deal(address(nftContract), contractBalance);

        vm.expectEmit(false, false, false, true);
        emit WithdrawAll(contractBalance);

        nftContract.withdrawAll();
    }

    function testEmitChangeOwner(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != nftContract.owner());

        vm.expectEmit(false, false, false, true);
        emit ChangeOwner(newOwner);

        nftContract.changeOwner(newOwner);
    }

    //--------------------------------------------------
    // Pause related
    //--------------------------------------------------
    function testCanPauzeAndUnpauseContract() public {
        assertEq(nftContract.paused(), false);
        nftContract.pauseContract();
        assertEq(nftContract.paused(), true);
        nftContract.unpauseContract();
        assertEq(nftContract.paused(), false);
    }

    function testCannotMintWhenContractIsPaused(bytes32[] memory proof) public {
        nftContract.pauseContract();

        vm.expectRevert(bytes('Pausable: paused'));
        nftContract.mint(address(1), 1, 1, proof);
    }
}