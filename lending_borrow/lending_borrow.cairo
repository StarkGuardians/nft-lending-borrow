// SPDX-License-Identifier: Not licensed
// OpenZeppelin Contracts for Cairo v0.7.0 (token/erc721/erc721.cairo)

// When `LegacyMap` is called with a non-existent key, it returns a struct with all properties are initialized to zero values.

use starknet::ContractAddress;
use starknet::contract_address_const;
use openzeppelin::token::erc20::interface::IERC20CamelDispatcher;


#[starknet::interface]
trait IERC721CamelCase<TState> {
    fn safe_transfer_from(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data_len: felt252,
        data: Span<felt252>
    );
    fn safeTransferFrom(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data_len: felt252,
        data: Span<felt252>
    );
    fn transferFrom(ref self: TState, from: ContractAddress, to: ContractAddress, tokenId: u256);
}


fn eth_contract() -> IERC20CamelDispatcher {
    IERC20CamelDispatcher {
        contract_address: contract_address_const::<
            0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        >(),
    }
}

#[starknet::contract]
mod LendingBorrow {
    use openzeppelin::token::erc721::interface::IERC721CamelOnlyDispatcherTrait;
    use openzeppelin::token::erc20::interface::IERC20CamelDispatcherTrait;
    use core::traits::DivEq;
    use core::num::traits::zero::Zero;
    use core::fmt::Display;
    use core::fmt::Debug;
    use core::array::SpanTrait;
    use super::IERC721CamelCase;
    use super::eth_contract;
    use core::bool;
    use core::array::ArrayTrait;
    use core::Zeroable;
    use core::clone::Clone;
    use core::option::OptionTrait;
    use core::traits::{Destruct, TryInto, Into,};
    use integer::{u256_from_felt252, U64IntoFelt252};
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, get_contract_address,
        contract_address_const, class_hash::ClassHash
    };
    use openzeppelin::{
        upgrades::UpgradeableComponent, upgrades::interface::IUpgradeable,
        introspection::src5::SRC5Component, introspection::interface::ISRC5,
        security::ReentrancyGuardComponent, access::ownable::OwnableComponent,
        access::ownable::interface::IOwnable, token::erc721::interface::IERC721ReceiverCamel,
        token::erc721::ERC721ReceiverComponent, token::erc721::interface::IERC721CamelOnlyDispatcher
    };


    use sgn_stake_master::interface::ILendingBorrow::{
        ILendingBorrow, ISetters, BorrowInfo, LendInfo, LendingsArray, BorrowsArray
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy, event: ReentrancyEvent);
    component!(path: ERC721ReceiverComponent, storage: erc721Receiver, event: Erc721ReceiverEvent);


    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5CamelImpl = SRC5Component::SRC5CamelImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ReceiverImpl =
        ERC721ReceiverComponent::ERC721ReceiverImpl<ContractState>;
    impl ERC721ReceiverInternalImpl = ERC721ReceiverComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        _lendingIds: LegacyMap<felt252, felt252>,
        _borrowIds: LegacyMap<felt252, felt252>,
        _userLendings: LegacyMap<(ContractAddress, felt252), felt252>,
        _userBorrows: LegacyMap<(ContractAddress, felt252), felt252>,
        _userLendingCount: LegacyMap<ContractAddress, felt252>,
        _userBorrowCount: LegacyMap<ContractAddress, felt252>,
        _isVerifiedCollection: LegacyMap<ContractAddress, bool>,
        _lendingById: LegacyMap<felt252, LendInfo>,
        _borrowById: LegacyMap<felt252, BorrowInfo>,
        _totalLended: u256,
        _lendingCount: felt252,
        _borrowCount: felt252,
        _totalBorrowed: u256,
        _protocolNonce: felt252,
        _performanceFee: felt252, //by basis point 150 %1.5
        _feeTreasury: ContractAddress,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        erc721Receiver: ERC721ReceiverComponent::Storage,
    }


    #[derive(Drop, starknet::Event)]
    struct Lended {
        lendingId: felt252,
        lender: ContractAddress,
        collectionAddress: ContractAddress,
        lendAmount: u256,
        duration: u64,
        yieldValue: u256,
        depositTime: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrowed {
        borrowId: felt252,
        lendId: felt252,
        borrower: ContractAddress,
        tokenIdOfCollateral: u256,
        borrowAmount: u256,
        borrowTime: u64,
    }


    #[derive(Drop, starknet::Event)]
    struct Repayed {
        borrowId: felt252,
        lendId: felt252,
        totalPaidInterest: u256,
        totalPaid: u256,
        time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Liqudiated {
        borrowId: felt252,
        lendId: felt252,
        time: u64,
    }


    #[derive(Drop, starknet::Event)]
    struct AssetsWithdrawn {
        lendId: felt252,
        time: u64
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Lended: Lended,
        Borrowed: Borrowed,
        Repayed: Repayed,
        Liqudiated: Liqudiated,
        AssetsWithdrawn: AssetsWithdrawn,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        ReentrancyEvent: ReentrancyGuardComponent::Event,
        #[flat]
        Erc721ReceiverEvent: ERC721ReceiverComponent::Event,
    }

    //const ONE_YEAR: u64 = 86400; // it's equals to one day, changed for testing purpose
    const ONE_YEAR: u64 = 31556926;

    extern fn u8_to_felt252(a: u8) -> felt252 nopanic;
    extern fn u128_to_felt252(a: u128) -> felt252 nopanic;
    extern fn contract_address_to_felt252(address: ContractAddress) -> felt252 nopanic;
    // point calculation = point / 10000 points per second
    #[constructor]
    fn constructor(
        ref self: ContractState, _owner: ContractAddress, treasuryAddr: ContractAddress
    ) {
        self._performanceFee.write(150);
        self._feeTreasury.write(treasuryAddr);
        self.src5.register_interface(0x150b7a02);
        self.erc721Receiver.initializer();
        self.ownable.initializer(_owner);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl BaseProtocol of ILendingBorrow<ContractState> {
        fn lend(
            ref self: ContractState,
            collection: ContractAddress,
            yieldValue: u256,
            lendAmount: u256,
            duration: u64
        ) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let this = get_contract_address();
            let now = get_block_timestamp();

            self.isCollectionVerified(collection);
            self._transferFundsFromUser(caller, this, lendAmount);
            let _lendingId = contract_address_to_felt252(caller)
                + now.into()
                + self._protocolNonce.read();

            self._isYieldBetweenLimits(yieldValue);
            self._isValidDuration(duration);

            let lendingInfo = LendInfo {
                lender: caller,
                collectionAddress: collection,
                lendAmount: lendAmount,
                duration: duration,
                yieldValue: yieldValue,
                depositTime: now,
                isAvailable: bool::True,
                borrowId: 0
            };

            let userLendingCount = self._userLendingCount.read(caller);
            let lendingCount = self._lendingCount.read();
            self._lendingCount.write(lendingCount + 1);
            self._lendingIds.write(lendingCount, _lendingId);
            self._userLendings.write((caller, userLendingCount), _lendingId);
            self._lendingById.write(_lendingId, lendingInfo);
            self._protocolNonce.write(self._protocolNonce.read() + 1);
            self._userLendingCount.write(caller, userLendingCount + 1);
            self._totalLended.write(self._totalLended.read() + lendAmount);

            self
                .emit(
                    Lended {
                        lendingId: _lendingId,
                        lender: caller,
                        collectionAddress: collection,
                        lendAmount: lendAmount,
                        duration: duration,
                        yieldValue: yieldValue,
                        depositTime: now,
                    }
                );

            self.reentrancy.end();
        }

        fn borrow(
            ref self: ContractState,
            collection: ContractAddress,
            tokenId: u256,
            lendingId: felt252,
            borrowAmount: u256
        ) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let this = get_contract_address();
            let now = get_block_timestamp();

            let lendingInfo = self._lendingById.read(lendingId);
            assert(lendingInfo.isAvailable == bool::True, 'lending is not available');
            assert(lendingInfo.collectionAddress == collection, 'collections doesnt match');
            assert(borrowAmount <= lendingInfo.lendAmount, 'borrow amount exceed limit');

            self.isCollectionVerified(collection);
            self._transferNft(collection, caller, this, tokenId);

            let _borrowId = contract_address_to_felt252(caller)
                + now.into()
                + self._protocolNonce.read();

            let lendingInfo = LendInfo {
                lender: lendingInfo.lender,
                collectionAddress: lendingInfo.collectionAddress,
                lendAmount: lendingInfo.lendAmount,
                duration: lendingInfo.duration,
                yieldValue: lendingInfo.yieldValue,
                depositTime: lendingInfo.depositTime,
                isAvailable: bool::False,
                borrowId: _borrowId
            };

            let _borrowInfo = BorrowInfo {
                lendId: lendingId,
                borrower: caller,
                tokenIdOfCollateral: tokenId,
                borrowTime: now,
                borrowAmount: borrowAmount,
                isRepayed: bool::False,
                isLiquidiated: bool::False,
            };

            let userBorrowCount = self._userBorrowCount.read(caller);
            let borrowCount = self._borrowCount.read();

            self._borrowCount.write(borrowCount + 1);
            self._borrowIds.write(borrowCount, _borrowId);
            self._borrowById.write(_borrowId, _borrowInfo);
            self._userBorrows.write((caller, userBorrowCount), _borrowId);
            self._userBorrowCount.write(caller, userBorrowCount + 1);

            self._lendingById.write(lendingId, lendingInfo);

            self._protocolNonce.write(self._protocolNonce.read() + 1);
            self._totalBorrowed.write(self._totalBorrowed.read() + borrowAmount);

            self._transferFundsFromTreasury(caller, borrowAmount);

            self
                .emit(
                    Borrowed {
                        borrowId: _borrowId,
                        lendId: lendingId,
                        borrower: caller,
                        tokenIdOfCollateral: tokenId,
                        borrowAmount: borrowAmount,
                        borrowTime: now,
                    }
                );

            self.reentrancy.end();
        }

        fn repay(ref self: ContractState, borrowPositionId: felt252) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let this = get_contract_address();
            let now = get_block_timestamp();

            let borrowInfo = self._borrowById.read(borrowPositionId);
            let lendingInfo = self._lendingById.read(borrowInfo.lendId);

            assert(caller == borrowInfo.borrower, 'caller is not borrower');
            assert(borrowInfo.isLiquidiated == bool::False, 'position liquidiated');
            assert(borrowInfo.isRepayed == bool::False, 'position repayed');

            let (totalPaid, totalPaidInterest, userInterest, protocolFee) = self
                .returnAmountOfDebtByBorrowId(borrowPositionId);

            self._transferFundsFromUser(caller, this, borrowInfo.borrowAmount);
            self._transferFundsFromUser(caller, lendingInfo.lender, userInterest);
            self._transferFundsFromUser(caller, self._feeTreasury.read(), protocolFee);

            let _lendingInfo = LendInfo {
                lender: lendingInfo.lender,
                collectionAddress: lendingInfo.collectionAddress,
                lendAmount: lendingInfo.lendAmount,
                duration: lendingInfo.duration,
                yieldValue: lendingInfo.yieldValue,
                depositTime: lendingInfo.depositTime,
                isAvailable: bool::True,
                borrowId: 0
            };

            let _borrowInfo = BorrowInfo {
                lendId: borrowInfo.lendId,
                borrower: borrowInfo.borrower,
                tokenIdOfCollateral: borrowInfo.tokenIdOfCollateral,
                borrowTime: borrowInfo.borrowTime,
                borrowAmount: borrowInfo.borrowAmount,
                isRepayed: bool::True,
                isLiquidiated: bool::False,
            };

            self
                ._transferNft(
                    lendingInfo.collectionAddress, this, caller, borrowInfo.tokenIdOfCollateral
                );

            self._lendingById.write(borrowInfo.lendId, _lendingInfo);
            self._borrowById.write(borrowPositionId, _borrowInfo);
            self._totalBorrowed.write(self._totalBorrowed.read() - borrowInfo.borrowAmount);

            self
                .emit(
                    Repayed {
                        borrowId: borrowPositionId,
                        lendId: borrowInfo.lendId,
                        totalPaidInterest: totalPaidInterest,
                        totalPaid: totalPaid,
                        time: now
                    }
                );

            self.reentrancy.end();
        }

        fn liquidiate(ref self: ContractState, borrowPositionId: felt252) {
            self.reentrancy.start();
            let this = get_contract_address();
            let now = get_block_timestamp();

            let borrowInfo = self._borrowById.read(borrowPositionId);
            let lendingInfo = self._lendingById.read(borrowInfo.lendId);
            let isTimePassed = borrowInfo.borrowTime + lendingInfo.duration;

            assert(now >= isTimePassed, 'condition is not met yet');
            assert(borrowInfo.isLiquidiated == bool::False, 'position already liquidiated');
            assert(borrowInfo.isRepayed == bool::False, 'position repayed');

            let _lendingInfo = LendInfo {
                lender: lendingInfo.lender,
                collectionAddress: lendingInfo.collectionAddress,
                lendAmount: lendingInfo.lendAmount,
                duration: lendingInfo.duration,
                yieldValue: lendingInfo.yieldValue,
                depositTime: lendingInfo.depositTime,
                isAvailable: bool::False,
                borrowId: 0
            };

            let _borrowInfo = BorrowInfo {
                lendId: borrowInfo.lendId,
                borrower: borrowInfo.borrower,
                tokenIdOfCollateral: borrowInfo.tokenIdOfCollateral,
                borrowTime: borrowInfo.borrowTime,
                borrowAmount: borrowInfo.borrowAmount,
                isRepayed: bool::False,
                isLiquidiated: bool::True,
            };

            self
                ._transferNft(
                    lendingInfo.collectionAddress,
                    this,
                    lendingInfo.lender,
                    borrowInfo.tokenIdOfCollateral
                );

            self._lendingById.write(borrowInfo.lendId, _lendingInfo);
            self._borrowById.write(borrowPositionId, _borrowInfo);
            self._totalBorrowed.write(self._totalBorrowed.read() - borrowInfo.borrowAmount);
            self._totalLended.write(self._totalLended.read() - borrowInfo.borrowAmount);

            self
                .emit(
                    Liqudiated { borrowId: borrowPositionId, lendId: borrowInfo.lendId, time: now, }
                );

            self.reentrancy.end();
        }

        fn withdraw_assets(ref self: ContractState, lendingPositionId: felt252) {
            self.reentrancy.start();
            let caller = get_caller_address();
            let now = get_block_timestamp();

            let lendingInfo = self._lendingById.read(lendingPositionId);

            assert(lendingInfo.isAvailable == bool::True, 'lending is not available');
            assert(lendingInfo.lender == caller, 'caller is not lender');

            let _lendingInfo = LendInfo {
                lender: lendingInfo.lender,
                collectionAddress: lendingInfo.collectionAddress,
                lendAmount: lendingInfo.lendAmount,
                duration: lendingInfo.duration,
                yieldValue: lendingInfo.yieldValue,
                depositTime: lendingInfo.depositTime,
                isAvailable: bool::False,
                borrowId: 0
            };

            self._lendingById.write(lendingPositionId, _lendingInfo);
            self._totalLended.write(self._totalLended.read() - lendingInfo.lendAmount);
            self._transferFundsFromTreasury(caller, lendingInfo.lendAmount);

            self.emit(AssetsWithdrawn { lendId: lendingPositionId, time: now, });

            self.reentrancy.end();
        }

        fn isCollectionVerified(self: @ContractState, collectionAddress: ContractAddress) -> bool {
            let _isVerified = self._isVerifiedCollection.read(collectionAddress);
            assert(_isVerified == bool::True, 'unverified collection');
            return _isVerified;
        }

        fn returnInterestOfBorrow(
            self: @ContractState, borrowId: felt252
        ) -> (u256, u256, u256, u256) {
            self.returnAmountOfDebtByBorrowId(borrowId)
        }


        fn getLending(self: @ContractState, lendingId: felt252) -> LendInfo {
            let lendingInfo = self._lendingById.read(lendingId);
            lendingInfo
        }

        fn getBorrow(self: @ContractState, borrowId: felt252) -> BorrowInfo {
            let borrowInfo = self._borrowById.read(borrowId);
            borrowInfo
        }

        fn totalLended(self: @ContractState) -> u256 {
            self._totalLended.read()
        }

        fn getBorrows(
            self: @ContractState, startIndex: felt252, endIndex: felt252
        ) -> Array<BorrowsArray> {
            let mut i: felt252 = startIndex;
            let mut borrowInfos = ArrayTrait::<BorrowsArray>::new();
            let borrowCount = self._borrowCount.read();

            loop {
                let borrowId = self._borrowIds.read(i);
                let _borrowInfo = self._borrowById.read(borrowId);
                let _borrowInfo = BorrowsArray {
                    borrowId: borrowId,
                    lendId: _borrowInfo.lendId,
                    borrower: _borrowInfo.borrower,
                    tokenIdOfCollateral: _borrowInfo.tokenIdOfCollateral,
                    borrowTime: _borrowInfo.borrowTime,
                    borrowAmount: _borrowInfo.borrowAmount,
                    isRepayed: _borrowInfo.isRepayed,
                    isLiquidiated: _borrowInfo.isLiquidiated,
                };
                if borrowCount == i {
                    break;
                }
                if i == endIndex {
                    break;
                }

                borrowInfos.append(_borrowInfo);

                i += 1;
            };

            borrowInfos
        }

        fn getLendings(
            self: @ContractState, startIndex: felt252, endIndex: felt252
        ) -> Array<LendingsArray> {
            let mut i: felt252 = startIndex;
            let mut lendingInfos = ArrayTrait::<LendingsArray>::new();
            let lendingCount = self._lendingCount.read();

            loop {
                let lendId = self._lendingIds.read(i);
                let _lendInfo = self._lendingById.read(lendId);
                let _lendingInfo = LendingsArray {
                    lendId: lendId,
                    lender: _lendInfo.lender,
                    collectionAddress: _lendInfo.collectionAddress,
                    lendAmount: _lendInfo.lendAmount,
                    duration: _lendInfo.duration,
                    yieldValue: _lendInfo.yieldValue,
                    depositTime: _lendInfo.depositTime,
                    isAvailable: _lendInfo.isAvailable,
                    borrowId: _lendInfo.borrowId
                };
                if lendingCount == i {
                    break;
                }
                if i == endIndex {
                    break;
                }

                lendingInfos.append(_lendingInfo);

                i += 1;
            };

            lendingInfos
        }

        fn getUserLendings(
            self: @ContractState, userAddr: ContractAddress, startIndex: felt252, endIndex: felt252
        ) -> Array<LendingsArray> {
            let mut i: felt252 = startIndex;
            let mut userLendingInfo = ArrayTrait::<LendingsArray>::new();
            let userLendingCount = self._userLendingCount.read(userAddr);
            loop {
                let userLendingId = self._userLendings.read((userAddr, i));
                let _lendingInfo = self._lendingById.read(userLendingId);
                let lendingInfo = LendingsArray {
                    lendId: userLendingId,
                    lender: _lendingInfo.lender,
                    collectionAddress: _lendingInfo.collectionAddress,
                    lendAmount: _lendingInfo.lendAmount,
                    duration: _lendingInfo.duration,
                    yieldValue: _lendingInfo.yieldValue,
                    depositTime: _lendingInfo.depositTime,
                    isAvailable: _lendingInfo.isAvailable,
                    borrowId: _lendingInfo.borrowId
                };
                if userLendingCount == i {
                    break;
                }
                if i == endIndex {
                    break;
                }

                userLendingInfo.append(lendingInfo);

                i += 1;
            };

            userLendingInfo
        }


        fn getUserBorrows(
            self: @ContractState, userAddr: ContractAddress, startIndex: felt252, endIndex: felt252
        ) -> Array<BorrowsArray> {
            let mut i: felt252 = startIndex;
            let mut userBorrowInfo = ArrayTrait::<BorrowsArray>::new();
            let userBorrowCount = self._userBorrowCount.read(userAddr);

            loop {
                let userBorrowId = self._userBorrows.read((userAddr, i));
                let _borrowInfo = self._borrowById.read(userBorrowId);
                let borrowInfo = BorrowsArray {
                    borrowId: userBorrowId,
                    lendId: _borrowInfo.lendId,
                    borrower: _borrowInfo.borrower,
                    tokenIdOfCollateral: _borrowInfo.tokenIdOfCollateral,
                    borrowTime: _borrowInfo.borrowTime,
                    borrowAmount: _borrowInfo.borrowAmount,
                    isRepayed: _borrowInfo.isRepayed,
                    isLiquidiated: _borrowInfo.isLiquidiated,
                };
                if i == userBorrowCount {
                    break;
                }
                if i == endIndex {
                    break;
                }

                userBorrowInfo.append(borrowInfo);

                i += 1;
            };

            userBorrowInfo
        }
    }


    #[abi(embed_v0)]
    impl ImplSetters of ISetters<ContractState> {
        fn setSettings(
            ref self: ContractState, feeTreasury: ContractAddress, performanceFee: felt252
        ) {
            self.ownable.assert_only_owner();
            self._feeTreasury.write(feeTreasury);
            self._performanceFee.write(performanceFee);
        }

        fn verifyCollection(ref self: ContractState, address: ContractAddress, shouldVerify: bool) {
            self.ownable.assert_only_owner();
            self._isVerifiedCollection.write(address, shouldVerify);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transferFundsFromUser(
            ref self: ContractState,
            fromUser: ContractAddress,
            toUser: ContractAddress,
            amount: u256
        ) {
            let isSuccess = eth_contract().transferFrom(fromUser, toUser, amount);
            assert(isSuccess == bool::True, 'funds transfer failed');
        }

        fn returnAmountOfDebtByBorrowId(
            self: @ContractState, borrowId: felt252
        ) -> (u256, u256, u256, u256) {
            let borrowInfo = self._borrowById.read(borrowId);
            let now = get_block_timestamp();
            let timeSpent = now - borrowInfo.borrowTime;
            let lendingInfo = self._lendingById.read(borrowInfo.lendId);
            let interestAmount = timeSpent.into()
                * (lendingInfo.yieldValue.into() * borrowInfo.borrowAmount / 100)
                / ONE_YEAR.into();
            let protocolFee = interestAmount * self._performanceFee.read().into() / 10000;

            return (
                borrowInfo.borrowAmount + interestAmount,
                interestAmount,
                interestAmount - protocolFee,
                protocolFee
            );
        }

        fn _transferNft(
            ref self: ContractState,
            collection: ContractAddress,
            fromUser: ContractAddress,
            toUser: ContractAddress,
            tokenId: u256
        ) {
            IERC721CamelOnlyDispatcher { contract_address: collection }
                .transferFrom(fromUser, toUser, tokenId);
        }

        fn _isYieldBetweenLimits(ref self: ContractState, yieldRate: u256) {
            assert(yieldRate < 50, 'yield limit exceed');
            assert(yieldRate > 1, 'yield min limit exceed');
        }

        fn _isValidDuration(ref self: ContractState, duration: u64) {
            assert(duration > 86400, 'must be longer than 1 day');
            assert(duration < 7889231, 'must be less than 3 months');
        }


        fn _transferFundsFromTreasury(
            ref self: ContractState, toUser: ContractAddress, amount: u256
        ) {
            let isSuccess = eth_contract().transfer(toUser, amount);
            assert(isSuccess == bool::True, 'funds transfer failed');
        }
    }
}
