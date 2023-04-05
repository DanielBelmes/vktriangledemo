import std/options

type QueueFamilyIndices* = object
    graphicsFamily*: Option[uint32]