# Bitpacking A Minesweeper Tile
###### 13/11/2024

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

So, 3 bytes per tile (`bool`s are stored as 1 byte values in Rust), and 1.56 billion tiles comes out to about 4.69GB of memory. That is not too bad, but honestly, I wasn't satisfied with that. But how do I compress data past individual bytes of data?

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

Check out [BitwiseCmd](https://bitwisecmd.com) if you you'd like to play around with bitwise operations to understand them a bit more.

## Bitpacked Layout

Bitpacking is a form of data compression, but honestly I'm not smart enough to know or care about how to actually use it for any practical application. However, I still used bitpacking to compress the 3 bytes of data per tile into 3 bits of data per tile. But, it isn't as simple as that as data must be byte aligned (or something like that). Because of that, even if my tile representation is 3 bits, the other 5 bits in a byte would be wasted. So, I must pack the multiple tiles into a byte to compensate. Since each tile is 3 bits, and there are 8 bits in a byte, 3 bytes is the lowest amount of bytes I can use to store a set of 3 bit data structures to have all bytes be fully used. That didn't make any sense, but I'm sure you get what I mean.

Because I need a minimum of 3 bytes to store 8 tiles for the most memory efficient tile representation, I store the data as an array of 3 bytes instead of 3 `bool`s to allow me to manipulate each individual bit.

```rust, noplayground
#[derive(Default)]
struct Tile {
    data: [u8; 3]
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

Next, we get the bit's position by multiplying the index by 3, since each tile is 3 bits in length. We then calculate the index of the byte by dividing the position by size of a byte, 8 bits, with the remainder being discarded. Bit offset is the amount of bits to shift the byte to the right in order to get the requested data into the last 3 bits, which can be calculated with `bit_position % 8`.

```rust, noplayground
let bit_position = index * 3;
let byte_index = bit_position / 8;
let bit_offset = bit_position % 8;
```

Now, let's actually get the data. We can index into the correct byte with `byte_index` and shift the bits to the right by `bit_offset` to get the target bits into the first positions of the byte. By using `&`, we can then mask the last three bits, storing them in a mutable variable.

```rust, noplayground
let mut result = (self.data[byte_index] >> bit_offset) & 0b111;
```

But what if the tile data is split between two different bytes? Well, we just have to fetch the remaining bits from the next byte. If `bit_offset` exceeds 5, then there must be data stored in the next byte over as a shift of 6 or more will only yield 1-2 relevant bits. So, within an if statement, we can extract the remaining bits from the next byte over. We index into `self.data` with  `byte_index + 1` to get the next byte, and then shift the bits to the left by the opposite value of `bit_offset` (within a range of 0 to 7), which can be calculated with `8 - bit_offset`. This will give the target bits padding so that we can mask the byte to extract the bits in their respective locations. Using the masked byte, we can then use `|=` (`|` but return the result into the first operand, like `+=`) to place the bits into the correct location without interacting with the other bits. This is why we had to offset the bits before masking them, so that when the OR operation was performed the bits would be placed in their respective positions and not interfere with the other bits.

```rust, noplayground
if bit_offset > 5 {
    result |= (self.data[byte_index + 1] << (8 - bit_offset)) & 0b111;
}
```

That was a lot of explaining, so let's put it together now and do an example. If none of that made sense, don't worry cause I wrote that as I was still trying to understand it myself :P. If this made no sense, feel free to contact me as I'd be happy to clear some things up or fix any mistakes I made while writing this.

```rust, noplayground
pub fn get(&self, index: usize) -> u8 {
    assert!(index < 8, "Index out of range");

    let bit_position = index * 3;
    let byte_index = bit_position / 8;
    let bit_offset = bit_position % 8;

    let mut result = (self.data[byte_index] >> bit_offset) & 0b111;

    if bit_offset > 5 {
        result |= (self.data[byte_index + 1] << (8 - bit_offset)) & 0b111;
    }
    result
}
```

Here we are accessing the sixth item via index 5.

```rust, noplayground
let tile = Tile {
    data: [0b0, 0b10000000, 0b111] // example data
};

tile.get(5)

impl Tile {
    pub fn get(&self, index: usize) -> u8 {
        assert!(index < 8, "Index out of range"); // 5 < 8, so this assert does nothing

        let bit_position = index * 3; // 15
        let byte_index = bit_position / 8; // 1 (remainder is discarded)
        let bit_offset = bit_position % 8; // 7

        /*
                10000000
           7 >> 00000001
        0111  & 00000001
        */
        let mut result = (self.data[byte_index] >> bit_offset) & 0b111;

        if bit_offset > 5 {
            /*
                    00000111
               1 << 00001110
            0111  & 00000110
            0001  | 00000111
            */
            result |= (self.data[byte_index + 1] << (8 - bit_offset)) & 0b111;
        }

        result // 00000111 / 0111 / 0b111 / 7
    }
}
```

For the field-specific getters, I just called the get method, masked the result, and then converted it to a `bool`. Here's an example with the `fn is_mine(&self, index: usize) -> bool` method:

```rust, noplayground
pub fn is_mine(&self, index: usize) -> bool {
    (self.get(index) & 0b1) != 0
}
```

### Setter

TODO

## Conclusion

TODO