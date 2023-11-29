use dojo_examples::models::{Direction, Vec2, ProduceData, FieldCell, FieldStartCell};

// define the interface
#[starknet::interface]
trait IActions<TContractState> {
    fn register_item(self: @TContractState, item: u32, produces: u32, merge: u32);
    fn register_start_cell(self: @TContractState, position: Vec2, item: u32);

    fn start(self: @TContractState);
    fn produce(self: @TContractState, position: Vec2);
    fn merge(self: @TContractState, p1: Vec2, p2: Vec2);
}

// dojo decorator
#[dojo::contract]
mod actions {
    const FIELD_SIZE_X: u32 = 7;
    const FIELD_SIZE_Y: u32 = 9;

    use starknet::{ContractAddress, get_caller_address};
    use dojo_examples::models::{Direction, Vec2, Vec2Impl, ProduceData, FieldCell, FieldStartCell};
    use dojo_examples::utils::next_position;
    use super::IActions;

    // declaring custom event struct
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Produced: Produced,
    }

    // declaring custom event struct
    #[derive(Drop, starknet::Event)]
    struct Produced {
        player: ContractAddress,
        position: Vec2
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _find_empty_cell(self: @ContractState) -> Vec2 {
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            
            let mut y: u32 = 1;

            let mut freeCell = Vec2 {x: 0, y: 0};

            loop {
                if y > FIELD_SIZE_Y || freeCell.x > 0 {
                    break;
                }
                let mut x: u32 = 1;
                loop {
                    if x > FIELD_SIZE_X {
                        break;
                    }

                    let mut newCell = get!(world, (player, Vec2 {x: x, y: y}), (FieldCell));
                    if (newCell.item_type == 0) {
                        freeCell = Vec2 {x: x, y: y};
                        break;
                    }
                    x = x + 1;
                };
                y = y + 1;
            };

            return freeCell;
        }
    }

    // impl: implement functions specified in trait
    #[external(v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn register_item(self: @ContractState, item: u32, produces: u32, merge: u32) {
            let world = self.world_dispatcher.read();

            set!(world, 
                (
                    ProduceData {
                        item_type: item,
                        produce: produces,
                        merge: merge
                    }
                )
            );
        }

        fn register_start_cell(self: @ContractState, position: Vec2, item: u32) {
            let world = self.world_dispatcher.read();

            set!(world, 
                (
                    FieldStartCell {
                        position: position,
                        item_type: item
                    }
                )
            );
        }

        fn start(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            let mut y: u32 = 1;
            
            loop {
                if y > FIELD_SIZE_Y {
                    break;
                }
                let mut x: u32 = 1;
                loop {
                    if x > FIELD_SIZE_X {
                        break;
                    }

                    let startCell = get!(world, (Vec2 {x: x, y: y}), (FieldStartCell));
                    if (startCell.item_type != 0) {
                        set!(world, (
                            FieldCell {
                                player: player,
                                position: startCell.position,
                                item_type: startCell.item_type
                            }
                        ))
                    }
                    x = x + 1;
                };
                y = y + 1;
            };

        }

        fn produce(self: @ContractState, position: Vec2) {
            
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            emit!(world, Produced { player, position });

            let mut cell = get!(world, (player, position), (FieldCell));
            assert(cell.item_type != 0, 'Empty cell to produce');

            let produceData = get!(world, (cell.item_type), (ProduceData));
            assert(produceData.produce != 0, 'Item cant produce');

            let freeCell = InternalFunctions::_find_empty_cell(self);
            assert(freeCell.x != 0, 'No space to produce');

            set!(world, 
                (
                    FieldCell {
                        player: player,
                        position: freeCell,
                        item_type: produceData.produce
                    }
                )
            );
        }

        fn merge(self: @ContractState, p1: Vec2, p2: Vec2) {
            assert(!p1.is_equal(p2), 'Same cell to merge');

            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            let mut cell1 = get!(world, (player, p1), (FieldCell));
            let mut cell2 = get!(world, (player, p2), (FieldCell));

            assert(cell1.item_type != 0 && cell2.item_type != 0, 'Empty cell to merge');
            assert(cell1.item_type == cell2.item_type, 'Cant merge different items');

            let mut itemData = get!(world, (cell1.item_type), (ProduceData));
            
            cell1.item_type = itemData.merge;
            cell2.item_type = 0;

            set!(world, (cell1));
            set!(world, (cell2));
        }
    }
}

#[cfg(test)]
mod tests {
    use starknet::class_hash::Felt252TryIntoClassHash;

    // import world dispatcher
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

    // import test utils
    use dojo::test_utils::{spawn_test_world, deploy_contract};

    // import models
    use dojo_examples::models::{field_cell, produce_data, field_start_cell};
    use dojo_examples::models::{Direction, Vec2};

    // import actions
    use super::{actions, IActionsDispatcher, IActionsDispatcherTrait};

    #[test]
    #[available_gas(300000000)]
    fn test_game() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        // models
        let mut models = array![field_cell::TEST_CLASS_HASH, produce_data::TEST_CLASS_HASH, field_start_cell::TEST_CLASS_HASH];

        // deploy world with models
        let world = spawn_test_world(models);

        // deploy systems contract
        let contract_address = world
            .deploy_contract('salt', actions::TEST_CLASS_HASH.try_into().unwrap());
        let actions_system = IActionsDispatcher { contract_address };
        
        actions_system.register_item(100, 2, 3);
        actions_system.register_item(2, 3, 4);

        actions_system.start();
        let p = Vec2 {
            x: 4,
            y: 5
        };
       // actions_system.produce(p);
       // actions_system.produce(Vec2 {x: 1, y: 1});
        //actions_system.merge(Vec2 {x: 1, y: 1}, Vec2 {x: 1, y: 2});

        // call move with direction right
        //actions_system.move(Direction::Right(()));

        //let right_dir_felt: felt252 = Direction::Right(()).into();

        // check moves
        //assert(moves.remaining == 99, 'moves is wrong');

        // get new_position
        //let new_position = get!(world, caller, Position);

        // check new position x
        //assert(new_position.vec.x == 11, 'position x is wrong');
    }
}
