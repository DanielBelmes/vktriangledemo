import std/options
import glfw
import vulkan
import glm/[mat, vec]
from errors import RuntimeException
from types import QueueFamilyIndices
from utils import cStringToString

const
    validationLayers = ["VK_LAYER_KHRONOS_validation"]
    vkInstanceExtensions = ["VK_KHR_portability_enumeration"]
    deviceExtensions = []
    WIDTH* = 800
    HEIGHT* = 600

when not defined(release):
    const enableValidationLayers = true
else:
    const enableValidationLayers = false

type 
    HelloWorldApp* = ref object
        instance: VkInstance
        window: GLFWWindow
        physicalDevice: VkPhysicalDevice
        graphicsQueue: VkQueue
        device: VkDevice
        surface: VkSurfaceKHR

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

    var availableLayers = newSeq[VkLayerProperties](layerCount)
    discard vkEnumerateInstanceLayerProperties(addr layerCount, addr availableLayers[0]);

    for layerName in validationLayers:
        var layerFound: bool = false
        for layerProperties in availableLayers:
            if cmp(layerName, cStringToString(layerProperties.layerName)) == 0:
                layerFound = true
                break

        if not layerFound:
            return false

    return true;

proc createInstance(self: HelloWorldApp) =
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

    if vkCreateInstance(addr createInfo, nil, addr self.instance) != VKSuccess:
        quit("failed to create instance")

proc createSurface(self: HelloWorldApp, instance: VkInstance) =
    if glfwCreateWindowSurface(instance, self.window, nil, addr self.surface) != VK_SUCCESS:
        raise newException(RuntimeException, "failed it create window surface")

proc findQueueFamilies(self: HelloWorldApp, device: VkPhysicalDevice): QueueFamilyIndices =
    var queueFamilyCount: uint32 = 0
    vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, nil)
    var queueFamilies: seq[VkQueueFamilyProperties] = newSeq[VkQueueFamilyProperties](queueFamilyCount)
    vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, addr queueFamilies[0])

    var index: uint32 = 0
    for queueFamily in queueFamilies:
        if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
            result.graphicsFamily = some(index)
            break

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

proc createLogicalDevice(self: HelloWorldApp) =
    let
        indices = self.findQueueFamilies(self.physicalDevice)
        queueFamily = indices.graphicsFamily.get
    var
        queuePriority = 1f
        queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()

    let deviceQueueCreateInfo: VkDeviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
        queueFamilyIndex = queueFamily,
        queueCount = 1,
        pQueuePriorities = queuePriority.addr
    )
    queueCreateInfos.add(deviceQueueCreateInfo)

    var
        deviceFeatures = newSeq[VkPhysicalDeviceFeatures](1)
        deviceExts = allocCStringArray(deviceExtensions)
        deviceCreateInfo = newVkDeviceCreateInfo(
        pQueueCreateInfos = queueCreateInfos[0].addr,
        queueCreateInfoCount = queueCreateInfos.len.uint32,
        pEnabledFeatures = deviceFeatures[0].addr,
        enabledExtensionCount = deviceExtensions.len.uint32,
        enabledLayerCount = 0,
        ppEnabledLayerNames = nil,
        ppEnabledExtensionNames = deviceExts
        )

    if vkCreateDevice(self.physicalDevice, deviceCreateInfo.addr, nil, self.device.addr) != VKSuccess:
        echo "failed to create logical device"

    deallocCStringArray(deviceExts)

    vkGetDeviceQueue(self.device, indices.graphicsFamily.get, 0, addr self.graphicsQueue)



proc initVulkan(self: HelloWorldApp) =
    vkPreload()
    self.createInstance()
    doAssert vkInit(self.instance)
    self.createSurface(self.instance)
    self.pickPhysicalDevice();
    self.createLogicalDevice();

proc mainLoop(self: HelloWorldApp) =
    while not windowShouldClose(self.window):
        glfwPollEvents()

proc cleanup(self: HelloWorldApp) = 
    vkDestroyDevice(self.device, nil); #destroy device before instance
    vkDestroyInstance(self.instance, nil);
    self.window.destroyWindow()
    glfwTerminate()

proc run*(self: HelloWorldApp) = 
    self.initWindow()
    self.initVulkan()
    self.mainLoop()
    self.cleanup()