import std/options
import nimgl/[glfw]
import vulkan
import glm/[mat, vec]

const
    validationLayers = ["VK_LAYER_KHRONOS_validation"]
    vkInstanceExtensions = ["VK_KHR_portability_enumeration"]
    WIDTH* = 800
    HEIGHT* = 600

type RuntimeException = object of Exception

type QueueFamilyIndices = object
    graphicsFamily: Option[uint32]

when not defined(release):
    const enableValidationLayers = true
else:
    const enableValidationLayers = false

proc toString(arr: openArray[char]): string =
    for c in items(arr):
        if c != '\0':
            result = result & c

type 
    HelloWorldApp* = ref object
        window: GLFWWindow
        instance: VkInstance
        physicalDevice: VkPhysicalDevice

proc initWindow(self: HelloWorldApp) =
    doAssert glfwInit()

    glfwWindowHint(GLFWClientApi, GLFWNoApi)
    glfwWindowHint(GLFWResizable, GLFWFalse)

    self.window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil)
    if self.window == nil:
        quit(-1)

proc checkValidationLayerSupport(): bool =
    var layerCount: uint32
    discard vkEnumerateInstanceLayerProperties(addr layerCount, nil);
    echo layerCount

    var availableLayers = newSeq[VkLayerProperties](layerCount)
    discard vkEnumerateInstanceLayerProperties(addr layerCount, addr availableLayers[0]);

    for layerName in validationLayers:
        var layerFound: bool = false
        for layerProperties in availableLayers:
            if cmp(layerName, toString(layerProperties.layerName)) == 0:
                layerFound = true
                break

        if not layerFound:
            return false

    return true;

proc createInstance(self: HelloWorldApp): VkInstance =
    var appInfo = newVkApplicationInfo(
        pApplicationName = "NimGL Vulkan Example",
        applicationVersion = vkMakeVersion(1, 0, 0),
        pEngineName = "No Engine",
        engineVersion = vkMakeVersion(1, 0, 0),
        apiVersion = vkApiVersion1_1
    )

    var glfwExtensionCount: uint32 = 0
    var glfwExtensions: cstringArray

    glfwExtensions = glfwGetRequiredInstanceExtensions(addr glfwExtensionCount)
    var extensions: seq[string]
    for ext in cstringArrayToSeq(glfwExtensions, glfwExtensionCount):
        extensions.add(ext)
    for ext in vkInstanceExtensions:
        extensions.add(ext)
    var allExtensions = allocCStringArray(extensions)


    var layerCount: uint32 = 0
    var enabledLayers: cstringArray = nil

    if enableValidationLayers:
        layerCount = uint32(validationLayers.len)
        enabledLayers = allocCStringArray(validationLayers)

    var createInfo = newVkInstanceCreateInfo(
        flags = VkInstanceCreateFlags(0x0000001),
        pApplicationInfo = addr appInfo,
        enabledExtensionCount = glfwExtensionCount + uint32(vkInstanceExtensions.len),
        ppEnabledExtensionNames = allExtensions,
        enabledLayerCount = layerCount,
        ppEnabledLayerNames = enabledLayers,
    )

    if enableValidationLayers and not checkValidationLayerSupport():
        raise newException(RuntimeException, "validation layers requested, but not available!") 

    if enableValidationLayers:
        deallocCStringArray(enabledLayers)

    deallocCStringArray(allExtensions)

    if vkCreateInstance(addr createInfo, nil, unsafeAddr result) != VKSuccess:
        quit("failed to create instance")

proc findQueueFamilies(self: HelloWorldApp, device: VkPhysicalDevice): QueueFamilyIndices =
    var queueFamilyCount: uint32 = 0
    vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, nil)
    var queueFamilies: seq[VkQueueFamilyProperties] = newSeq[VkQueueFamilyProperties](queueFamilyCount)
    vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, addr queueFamilies[0])

    var index: uint32 = 0
    for queueFamily in queueFamilies:
        if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
            result.graphicsFamily = some(index)

proc isDeviceSuitable(self: HelloWorldApp, device: VkPhysicalDevice): bool =
    var deviceProperties: VkPhysicalDeviceProperties
    vkGetPhysicalDeviceProperties(device, deviceProperties.addr)
    var indicies: QueueFamilyIndices = self.findQueueFamilies(device)

    return indicies.graphicsFamily.isSome

proc pickPhysicalDevice(self: HelloWorldApp) =
    var deviceCount: uint32 = 0
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, nil)
    if(deviceCount == 0):
        raise newException(RuntimeException, "failed to find GPUs with Vulkan support!")
    var devices: seq[VkPhysicalDevice] = newSeq[VkPhysicalDevice](deviceCount)
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, addr devices[0])
    for device in devices:
        if self.isDeviceSuitable(device):
            self.physicalDevice = device
            return

    raise newException(RuntimeException, "failed to find a suitable GPU!")



proc initVulkan(self: HelloWorldApp) =
    vkPreload()
    self.instance = self.createInstance()
    doAssert vkInit(self.instance)
    self.pickPhysicalDevice();

proc mainLoop(self: HelloWorldApp) =
    while not windowShouldClose(self.window):
        glfwPollEvents()

proc cleanup(self: HelloWorldApp) = 
    vkDestroyInstance(self.instance, nil);
    self.window.destroyWindow()
    glfwTerminate()

proc run*(self: HelloWorldApp) = 
    self.initWindow()
    self.initVulkan()
    self.mainLoop()
    self.cleanup()