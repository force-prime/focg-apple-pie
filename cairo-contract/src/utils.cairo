use dojo_examples::models::{Vec2, Direction};

fn next_position(mut position: Vec2, direction: Direction) -> Vec2 {
    match direction {
        Direction::None(()) => {
            return position;
        },
        Direction::Left(()) => {
            position.x -= 1;
        },
        Direction::Right(()) => {
            position.x += 1;
        },
        Direction::Up(()) => {
            position.y -= 1;
        },
        Direction::Down(()) => {
            position.y += 1;
        },
    };

    position
}
