# Bitpacking A Minesweeper Tile
###### 14/11/2024

So I've been working on a Minesweeper engine with the hope that I can produce the best possible Minesweeper backend. One of the core ideas of this implementation is that I can scale this board to ridiculous sizes in more than just 2 dimensions. Just for scale, a friend of mine set a goal for my engine: load and play a board of 69x69x69x69x69 tiles in size with 20% mine density. That's a total tile count of 1,564,031,349 containing 312,806,270 mines. For reference, a classic expert minesweeper board is 30x16 with 99 mines, and the variant I most often play is 30x30 with 160 mines. Basically, time to put way too much effort into writing a game of minesweeper. I'll write another post about how I'm implementing a board to support this tile, but that's not what this post is about.

So originally, I my tile struct was composed of a `u16` and 3 `bool` values. The `u16` was used to store neighbouring mine values, but that can be eliminated as that can be recalculated on the fly as it is only relevant for revealed, non-mine tiles. The 3 `bool` values each represented a property of the tile: is the tile a mine, is the tile revealed, and is the tile flagged. I'm going to skip over original implementation and thought process of bitpacking with the `u16` as the `u16` is eventually removed.

```rust, noplayground
#[derive(Default)]
struct Tile {
    is_mine: bool,
    revealed: bool,
    flagged: bool
}
```

So, 3 bytes per tile (`bool`s are stored as 1 byte values in Rust), and 1.56 billion tiles comes out to about 4.69GB[^note] of memory. That is not too bad, but honestly, I wasn't satisfied with that. But how do I compress data past individual bytes of data?

I don't think anyone will ask, but the reason I didn't use [`bitvec`](https://crates.io/crates/bitvec) or something similar is because I completely forgot that there are people way smarter than me that probably already did what I wanted. In hindsight, I probably should have checked first before dedicating so much time into this, but it was very fun to learn and put this together and I do believe that this implementation may be a bit more efficient than an implementation in `bitvec`. That's mostly because this is a fixed, relatively small chunk of data I'm manipulating, so the overhead from `bitvec` might be more noticeable and not worth it especially when scaled to the proportions I want to use this data structure at. Honestly, I don't really know and I'm too lazy to check so I guess I'll never know.

## Bits

The content passed this point is going to involve bit manipulation, so I'll give a quick rundown of bits and bitwise operations.

One bit is either 0 or 1, and 1 byte is made up of 8 bits. The most significant bit refers to the leftmost bit in a byte (**0**1000101), whereas the least significant bit refers to the rightmost bit in a byte (0100010**1**). Bits in a byte are counted from right to left, so `00000001` would be 1 and `10000000` would be 128. In Rust, binary is represented as `0bx`, where x is the bits. So, `0b1` represents 1, `0n100` represents 4, so on and so forth.

Below is a table containing a brief description and example of the bitwise operations that will be used:

Operator | Description | Example
-|-|-
NOT (!) | Invert a bit | `!1 = 0`
AND (&) | If the both bits are 1, return a 1, otherwise return a 0 | `0100 & 1111 = 0100`
OR (\|) | If one or more bits are 1, return a 1 | `0110 \| 0001 = 0111`
LEFT SHIFT (<<) | Move all bits in a byte to the left, putting 0s in the place of the discarded bits | `1111 << 2 = 1100`
RIGHT SHIFT (>>) | Move all bits in a byte to the right, putting 0s in the place of the discarded bits | `1111 >> 1 = 0111`

Check out [BitwiseCmd](https://bitwisecmd.com) if you you'd like to play around with bitwise operations to understand them a bit more. (no pun intended)

## Bitpacked Layout

Bitpacking is a form of data compression, but honestly I'm not smart enough to know or care about how to actually use it for any practical application. However, I still used bitpacking to compress the 3 bytes of data per tile into 3 bits of data per tile. But, it isn't as simple as that as data must be byte aligned (or something like that). Because of that, even if my tile representation is 3 bits, the other 5 bits in a byte would be wasted. So, I must pack the multiple tiles into a byte to compensate. Since each tile is 3 bits, and there are 8 bits in a byte, 3 bytes is the lowest amount of bytes I can use to store a set of 3 bit data structures to have all bytes be fully used. That didn't make any sense, but I'm sure you get what I mean.

Because I need a minimum of 3 bytes to store 8 tiles for the most memory efficient tile representation, I store the data as an array of 3 bytes instead of 3 `bool`s to allow me to manipulate each individual bit.

```rust, noplayground
#[derive(Default)]
struct Tile {
    tile_data: [u8; 3]
}
```

In binary, the array would appear as so: `[00000000, 00000000, 00000000]`. I chose to order the values by least significant bit (right to left) because it was a little bit easier to work with, so from this point on the order of the bytes will be reversed so that the data appears properly ordered from right to left across bytes. That means that byte 0 in the array is in the position of byte 2, and vice versa. So, the byte array `[00000000, 00000001, 00000010]` will be displayed as `[00000010, 00000001, 00000000]`.

So, each tile is represented as 3 bits, and is tightly packed into these 3 bytes. So, the byte array will appear as so (the numbers just represent the groups of bits that each represent a tile): `[77766655, 54443332, 22111000]`.

## Using the Data Structure

So, how does one actually get and set the data out of this tile implementation? The data must be handled via getter and setter methods to prevent invalid operations or inaccurate readings on the user's end. Each tile is retrieved or modified via an index between 0 and 7, which is inputted as a parameter on the getter or setter method. The first bit in a tile is used as the `is_mine` flag, the second as the `revealed` flag, and the third as the `flagged` flag.

### Getter

First off, let's define a general `get` method that will return 1 tile based on the index provided. The method will require an index and output a single byte containing the requested tile data. An `assert!` macro can be used to guarantee that `index` is within bounds.

```rust, noplayground
pub fn get(&self, index: usize) -> u8 {
    assert!(index < 8, "Index out of range");
}
```

Next, we get the tile's position by multiplying the index by 3, since each tile is 3 bits in length. We then calculate the index of the byte by dividing the position by size of a byte, 8 bits, with the remainder being discarded. Bit offset is the amount of bits to shift the byte to the right in order to get the requested data into the last 3 bits, which can be calculated with `bit_position % 8`.

```rust, noplayground
let bit_position = index * 3;
let byte_index = bit_position / 8;
let bit_offset = bit_position % 8;
```

Now, let's actually get the data. We can index into the correct byte with `byte_index` and shift the bits to the right by `bit_offset` to get the tile bits into the first positions of the byte. By using `&`, we can then mask the last three bits, storing them in a mutable variable.

```rust, noplayground
let mut result = (self.tile_data[byte_index] >> bit_offset) & 0b111;
```

But what if the tile data is split between two different bytes? Well, we just have to fetch the remaining bits from the next byte. If `bit_offset` exceeds 5, then there must be data stored in the next byte over as a shift of 6 or more will only yield 1-2 relevant bits. So, within an if statement, we can extract the remaining bits from the next byte over. We index into `self.tile_data` with  `byte_index + 1` to get the next byte, and then shift the bits to the left by the opposite value of `bit_offset` (within a range of 0 to 7), which can be calculated with `8 - bit_offset`. This will give the target bits padding so that we can mask the byte to extract the bits in their respective locations. Using the masked byte, we can then use `|=` (`|` but return the result into the first operand, like `+=`) to place the bits into the correct location without interacting with the other bits. This is why we had to offset the bits before masking them, so that when the OR operation was performed the bits would be placed in their respective positions and not interfere with the other bits.

```rust, noplayground
if bit_offset > 5 {
    result |= (self.tile_data[byte_index + 1] << (8 - bit_offset)) & 0b111;
}
```

That was a lot of explaining, so let's put it together now and do an example. If none of that made sense, maybe this example will help. If that doesn't help, then honestly idk what to tell you.

```rust, noplayground
pub fn get(&self, index: usize) -> u8 {
    assert!(index < 8, "Index out of range");

    let bit_position = index * 3;
    let byte_index = bit_position / 8;
    let bit_offset = bit_position % 8;

    let mut result = (self.tile_data[byte_index] >> bit_offset) & 0b111;

    if bit_offset > 5 {
        result |= (self.tile_data[byte_index + 1] << (8 - bit_offset)) & 0b111;
    }
    result
}
```

Here we are accessing the sixth item via index 5.

```rust, noplayground
let tile = Tile {
    tile_data: [0b0, 0b10000000, 0b111] // example data
};

tile.get(5)

impl Tile {
    pub fn get(&self, index: usize) -> u8 {
        assert!(index < 8, "Index out of range");

        let bit_position = index * 3; // 15
        let byte_index = bit_position / 8; // 1 (remainder is discarded)
        let bit_offset = bit_position % 8; // 7

        /*
                10000000
           7 >> 00000001
        0111  & 00000001
        */
        let mut result = (self.tile_data[byte_index] >> bit_offset) & 0b111;

        if bit_offset > 5 {
            /*
                    00000111
               1 << 00001110
            0111  & 00000110
            0001 |= 00000111
            */
            result |= (self.tile_data[byte_index + 1] << (8 - bit_offset)) & 0b111;
        }

        result // 00000111 / 0111 / 0b111 / 7
    }
}
```

For the field-specific getters, I just called the get method, masked the result, and then converted it to a `bool`. Here's an example with the `is_mine` method:

```rust, noplayground
pub fn is_mine(&self, index: usize) -> bool {
    (self.get(index) & 0b1) != 0
}
```

### Setter

The setter method uses a lot of similar techniques as the getters, but now overwrites bits instead of reading bits. The method will again take an index, but now also takes a byte as a parameter. The `assert!` macro will again be used to ensure index is within bounds. We will also mask the last 3 bits of the input byte in order to eliminate any accidental writing to bits outside of the targeted tile.

```rust, noplayground
pub fn set(&mut self, index: usize, mut byte: u8) {
    assert!(index < 8, "Index out of range");
    byte &= 0b111;
}
```

The `bit_position`, `byte_index`, and `bit_offset` have the exact same implementation in the setters as they do the getters, so I'll omit their explanation here.

We can now get on to preparing the target byte and the input byte for writing. First, we need to clear the relevant tile's bits within the target byte so that we can properly write to them. We can create a mask by first shifting 3 1 bits (`0b111`) to the correct position by using `bit_offset` instead of shifting the byte itself with `bit_offset` in order to prevent messing with other tiles' data. Then, we can use the `!` operator we can invert the mask and use the `&=` operation to clear the relevant bits without touching the other data in the target byte.

```rust, noplayground
self.tile_data[byte_index] &= !(0b111 << bit_offset);
```

Next, we have to prepare the bits that will be written. We can shift the bits into the correct position by using `bit_offset` again and use `|=` to overwrite the bits into the correct position within the target byte without interfering with other bits.

```rust, noplayground
self.tile_data[byte_index] |= byte << bit_offset;
```

For the tiles that have their data stored across bytes, we again have to create a special case for them. The code used to write the remaining bits is mostly just a combination of the getter stray bit logic and the recently explained overwriting logic. We must another create a mask for the bits, but this time we shift it to the right cover the target bits rather than shift the target bits into position like in the getter implementation. This is again done by calculating the inverse of `bit_offset` within a range of 0-7. We can then invert the mask and apply it with the `&=` operator to clear the bits we'd like to write to. Then, we can do the same thing to the input byte but use `|=` to safely write our input bits to the desired bits.

```rust, noplayground
if bit_offset > 5 {
    self.tile_data[byte_index + 1] &= !(0b111 >> (8 - bit_offset));
    self.tile_data[byte_index + 1] |= byte >> (8 - bit_offset);
}
```

Putting this together gives us our tile set function:

```rust, noplayground
pub fn set(&mut self, index: usize, mut byte: u8) {
    assert!(index < 8, "Index out of range");
    byte &= 0b111;

    let bit_position = index * 3;
    let byte_index = bit_position / 8;
    let bit_offset = bit_position % 8;

    self.tile_data[byte_index] &= !(0b111 << bit_offset);
    self.tile_data[byte_index] |= byte << bit_offset;

    if bit_offset > 5 {
        self.tile_data[byte_index + 1] &= !(0b111 >> (8 - bit_offset));
        self.tile_data[byte_index + 1] |= byte >> (8 - bit_offset);
    }
}
```

Example time!

```rust, noplayground
let mut tile = Tile {
    tile_data: [0; 3]
}

tile.set(2, 221); // 11011101

impl Tile {
    pub fn set(&mut self, index: usize, mut byte: u8) {
        assert!(index < 8, "Index out of range");
        /*
               11011101
        0111 & 00000101
        */
        byte &= 0b111;

        let bit_position = index * 3; // 6
        let byte_index = bit_position / 8; // 0
        let bit_offset = bit_position % 8; // 6

        /*
             00000111
        6 << 11000000
           ! 00111111
        0 &= 00000000
        */
        self.tile_data[byte_index] &= !(0b111 << bit_offset);
        /*
             00000101
        6 << 01000000
        0 |= 01000000
        */
        self.tile_data[byte_index] |= byte << bit_offset;


        if bit_offset > 5 {
            /*
                 00000111
            2 >> 00000001
               ! 11111110
            0 &= 00000000
            */
            self.tile_data[byte_index + 1] &= !(0b111 >> (8 - bit_offset));
            /*
                 00000101
            2 >> 00000001
            0 |= 00000001            
            */
            self.tile_data[byte_index + 1] |= byte >> (8 - bit_offset);
        }

        // self.tile_data = [0, 0b01000000, 0b1]
    }
}
```

Now, the individual getters are a bit simpler. Since the method only sets a singular bit there's no need for the if statement. We can also now take a `bool` as an input (we can cast it to a bit using `as u8`) and lower mask size to a singular bit. A different bit within a tile can be targeted by adding an offset to `bit_position`. An offset of 2 can be used to access the `flagged` bit, an offset of 1 can be used to access the `revealed` bit, and no offset accesses the `is_mine` bit. Here's an example with `set_flagged`:

```rust, noplayground
pub fn set_flagged(&mut self, index: usize, bit: bool) -> () {
    assert!(index < 8, "Index out of range");

    let bit_position = index * 3 + 2;
    let byte_index = bit_position / 8;
    let bit_offset = bit_position % 8;

    self.tile_data[byte_index] &= !(1 << bit_offset);
    self.tile_data[byte_index] |= (bit as u8) << bit_offset;
}
```

I don't think a detailed example is necessary as it's basically just the same as the regular `set` method, just with one bit. However, having 3 copies of nearly identical methods isn't ideal. I could create a singular method with an offset parameter and stuff, but I wanted to have uniquely named methods and I also wanted to try making a macro for once.

## MACRO JUMPSCARE

Mkay so basically the macro just takes 2 parameters, an identifier (the name of the method) and an offset in bits. This macro isn't intended for public use, it's just used to eliminate the 27 nearly identical lines by simplifying it too 3 nearly identical lines. For that reason, the `$offset` parameter is not type checked or bound checked as that would require some extra stuff that would impact performance (probably, idk I was just too lazy to deal with it tbh).

```rust, noplayground
macro_rules! bit_setter_method_builder {
    [$name:ident, $offset:expr] => {
        pub fn $name(&mut self, index: usize, bit: bool) -> () {
            assert!(index < 8, "Index out of range");

            let bit_position = index * 3 + $offset;
            let byte_index = bit_position / 8;
            let bit_offset = bit_position % 8;

            self.tile_data[byte_index] &= !(1 << bit_offset);
            self.tile_data[byte_index] |= (bit as u8) << bit_offset;
        }
    };
}
```

This macro can be put inside of the `impl` block for my `Tile` struct, and the compiler will even recognize it for syntax highlighting and parameter checks! I'm going to assume you can understand how this macro works as it's not particularly complex. Heck, you know what? I'm going to make a macro for the basically duplicate flag getter methods as well. I won't even call `get` cause it has an unnecessary if statement and idk if the compiler gets rid of it or not.

```rust, noplayground
macro_rules! bit_getter_method_builder {
    [$name:ident, $tile_bit_mask:expr] => {
        pub fn $name(&self, index: usize) -> bool {
            assert!(index < 8, "Index out of range");

            let bit_position = index * 3;
            let byte_index = bit_position / 8;
            let bit_offset = bit_position % 8;

            ((self.tile_data[byte_index] >> bit_offset) & $tile_bit_mask) != 0
        }
    };
}
```

Now I can just put the macros into my `impl` block!

```rust, noplayground
impl Tile {
    bit_getter_method_builder!(is_mine, 1);
    bit_getter_method_builder!(revealed, 3);
    bit_getter_method_builder!(flagged, 7);

    bit_setter_method_builder!(set_mine, 0);
    bit_setter_method_builder!(set_revealed, 1);
    bit_setter_method_builder!(set_flagged, 2);
}
```

## Conclusion

So, now that you have hopefully read my meticulous and incredibly detailed explanation on how I implemented an interface for this ridiculous structure, how much memory does this take up? Well, with 1.56 billion tiles and 3 bytes per 8 tiles, this implementation takes up about 586.5MB[^note] of memory. That's nearly an 8x increase in memory efficiency! Not too bad if I do say so myself. It's more computationally demanding due to the extra steps required to read and write data, but it's definitely an insane increase in memory efficiency that I will gladly implement for a tiny bit of extra processing. Actually using and processing this tile on the scale I'm hoping to will definitely be a bit of a challenge (maybe?), but I'm still very happy with how this ended up.

Here's the all the code I've covered in this post put together:

```rust, noplayground
macro_rules! bit_getter_method_builder {
    [$name:ident, $tile_bit_mask:expr] => {
        pub fn $name(&self, index: usize) -> bool {
            assert!(index < 8, "Index out of range");

            let bit_position = index * 3;
            let byte_index = bit_position / 8;
            let bit_offset = bit_position % 8;

            ((self.tile_data[byte_index] >> bit_offset) & $tile_bit_mask) != 0
        }
    };
}

macro_rules! bit_setter_method_builder {
    [$name:ident, $offset:expr] => {
        pub fn $name(&mut self, index: usize, bit: bool) -> () {
            assert!(index < 8, "Index out of range");

            let bit = bit as u8;

            let bit_position = index * 3 + $offset;
            let byte_index = bit_position / 8;
            let bit_offset = bit_position % 8;

            self.tile_data[byte_index] &= !(1 << bit_offset);
            self.tile_data[byte_index] |= bit << bit_offset;
        }
    };
}

#[derive(Default)]
pub struct Tile {
    tile_data: [u8; 3],
}

impl BitpackedGridTile {
    pub fn get(&self, index: usize) -> u8 {
        assert!(index < 8, "Index out of range");

        let bit_position = index * 3;
        let byte_index = bit_position / 8;
        let bit_offset = bit_position % 8;

        let mut result = (self.tile_data[byte_index] >> bit_offset) & 0b111;
        if bit_offset > 5 {
            result |= (self.tile_data[byte_index + 1] << (8 - bit_offset)) & 0b111;
        }

        result
    }

    pub fn set(&mut self, index: usize, mut byte: u8) {
        assert!(index < 8, "Index out of range");
        byte &= 0b111;

        let bit_position = index * 3;
        let byte_index = bit_position / 8;
        let bit_offset = bit_position % 8;

        self.tile_data[byte_index] &= !(0b111 << bit_offset);
        self.tile_data[byte_index] |= byte << bit_offset;

        if bit_offset > 5 {
            self.tile_data[byte_index + 1] &= !(0b111 >> (8 - bit_offset));
            self.tile_data[byte_index + 1] |= byte >> (8 - bit_offset);
        }
    }

    bit_getter_method_builder!(is_mine, 1);
    bit_getter_method_builder!(revealed, 3);
    bit_getter_method_builder!(flagged, 7);

    bit_setter_method_builder!(set_mine, 0);
    bit_setter_method_builder!(set_revealed, 1);
    bit_setter_method_builder!(set_flagged, 2);
}
```

Well, I'm finally done yapping. I hope you enjoyed my unnecessarily detailed exploration of bitpacking! Maybe next time I'll write a little less so that more than 1 person will ever read my posts...

[^note]: This is just an estimate of exclusively the data structures (no other program overhead) calculated with some math