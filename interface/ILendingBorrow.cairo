use starknet::ContractAddress;

#[derive(Drop, starknet::Store, Serde, Copy)]
struct BorrowInfo {
    lendId: felt252,
    borrower: ContractAddress,
    tokenIdOfCollateral: u256,
    borrowTime: u64,
    borrowAmount: u256,
    isRepayed: bool,
    isLiquidiated: bool,
}

#[derive(Drop, starknet::Store, Serde, Copy)]
struct LendInfo {
    lender: ContractAddress,
    collectionAddress: ContractAddress,
    lendAmount: u256,
    duration: u64,
    yieldValue: u256,
    depositTime: u64,
    isAvailable: bool,
    borrowId: felt252
}


#[derive(Drop, starknet::Store, Serde, Copy)]
struct LendingsArray {
    lendId: felt252,
    lender: ContractAddress,
    collectionAddress: ContractAddress,
    lendAmount: u256,
    duration: u64,
    yieldValue: u256,
    depositTime: u64,
    isAvailable: bool,
    borrowId: felt252
}

#[derive(Drop, starknet::Store, Serde, Copy)]
struct BorrowsArray {
    borrowId: felt252,
    lendId: felt252,
    borrower: ContractAddress,
    tokenIdOfCollateral: u256,
    borrowTime: u64,
    borrowAmount: u256,
    isRepayed: bool,
    isLiquidiated: bool,
}

#[starknet::interface]
trait ILendingBorrow<TState> {
    fn isCollectionVerified(self: @TState, collectionAddress: ContractAddress,) -> bool;
    fn getLendings(self: @TState, startIndex: felt252, endIndex: felt252) -> Array<LendingsArray>;
    fn getBorrows(self: @TState, startIndex: felt252, endIndex: felt252) -> Array<BorrowsArray>;
    fn getLending(self: @TState, lendingId: felt252) -> LendInfo;
    fn returnInterestOfBorrow(self: @TState, borrowId: felt252) -> (u256, u256, u256, u256);
    fn getBorrow(self: @TState, borrowId: felt252) -> BorrowInfo;
    fn totalLended(self: @TState) -> u256;
    fn getUserLendings(
        self: @TState, userAddr: ContractAddress, startIndex: felt252, endIndex: felt252
    ) -> Array<LendingsArray>;
    fn getUserBorrows(
        self: @TState, userAddr: ContractAddress, startIndex: felt252, endIndex: felt252
    ) -> Array<BorrowsArray>;
    fn withdraw_assets(ref self: TState, lendingPositionId: felt252);
    fn liquidiate(ref self: TState, borrowPositionId: felt252);
    fn repay(ref self: TState, borrowPositionId: felt252);
    fn borrow(
        ref self: TState,
        collection: ContractAddress,
        tokenId: u256,
        lendingId: felt252,
        borrowAmount: u256
    );
    fn lend(
        ref self: TState,
        collection: ContractAddress,
        yieldValue: u256,
        lendAmount: u256,
        duration: u64
    );
}


#[starknet::interface]
trait ISetters<TState> {
    fn setSettings(ref self: TState, feeTreasury: ContractAddress, performanceFee: felt252);
    fn verifyCollection(ref self: TState, address: ContractAddress, shouldVerify: bool);
}
