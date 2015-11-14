static mut seed: u64 = 19940046431; //259261034506304368955239; //1706322144714608529217229883707268827757977089;

/// Generate pseudo random number
pub fn rand() -> usize {
    seed ^= seed << 12;
    seed ^= seed << 25;
    seed ^= seed << 27;
    seed = seed * 82724793451 + 12345;
    seed as usize % ::core::usize::MAX
}

/// Generate pseudo random number via seed
pub fn srand(s: usize) {
    seed = s as u64;
}
