pub const Color = enum(u16) {
    Default = 0x00,
    Black = 0x01,
    Red = 0x02,
    Green = 0x03,
    Yellow = 0x04,
    Blue = 0x05,
    Magenta = 0x06,
    Cyan = 0x07,
    White = 0x08,
};

pub const Attribute = enum(u16) {
    Bold = 0x0100,
    Underline = 0x0200,
    Reverse = 0x0400,
};
