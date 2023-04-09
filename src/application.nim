{.experimental: "codeReordering".}
import std/options
import glfw
import sets
import bitops
import vulkan
#import glm/[mat, vec]
from errors import RuntimeException
import types
from utils import cStringToString

const
    validationLayers = ["VK_LAYER_KHRONOS_validation"]
    vkInstanceExtensions = ["VK_KHR_portability_enumeration"]
    deviceExtensions = ["VK_KHR_portability_subset","VK_KHR_swapchain"]
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
        surface: VkSurfaceKHR
        physicalDevice: VkPhysicalDevice
        graphicsQueue: VkQueue
        presentQueue: VkQueue
        device: VkDevice
        swapChain: VkSwapchainKHR
        swapChainImages: seq[VkImage]
        swapChainImageFormat: VkFormat
        swapChainExtent: VkExtent2D
        swapChainImageViews: seq[VkImageView]
        pipelineLayout: VkPipelineLayout
        renderPass: VkRenderPass
        graphicsPipeline: VkPipeline

proc initWindow(self: HelloWorldApp) =
    doAssert glfwInit()
    doAssert glfwVulkanSupported()

    glfwWindowHint(GLFWClientApi, GLFWNoApi)

    self.window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil, icon = false)
    if self.window == nil:
        quit(-1)

proc checkValidationLayerSupport(): bool =
    var layerCount: uint32
    discard vkEnumerateInstanceLayerProperties(addr layerCount, nil)

    var availableLayers = newSeq[VkLayerProperties](layerCount)
    discard vkEnumerateInstanceLayerProperties(addr layerCount, addr availableLayers[0])

    for layerName in validationLayers:
        var layerFound: bool = false
        for layerProperties in availableLayers:
            if cmp(layerName, cStringToString(layerProperties.layerName)) == 0:
                layerFound = true
                break

        if not layerFound:
            return false

    return true

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

    if enableValidationLayers and not enabledLayers.isNil:
        deallocCStringArray(enabledLayers)

    if not allExtensions.isNil:
        deallocCStringArray(allExtensions)

    if vkCreateInstance(addr createInfo, nil, addr self.instance) != VKSuccess:
        quit("failed to create instance")

proc createSurface(self: HelloWorldApp) =
    if glfwCreateWindowSurface(self.instance, self.window, nil, addr self.surface) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create window surface")

proc checkDeviceExtensionSupport(self: HelloWorldApp, pDevice: VkPhysicalDevice): bool =
    var extensionCount: uint32
    discard vkEnumerateDeviceExtensionProperties(pDevice, nil, addr extensionCount, nil)
    var availableExtensions: seq[VkExtensionProperties] = newSeq[VkExtensionProperties](extensionCount)
    discard vkEnumerateDeviceExtensionProperties(pDevice, nil, addr extensionCount, addr availableExtensions[0])
    var requiredExtensions: HashSet[string] = deviceExtensions.toHashSet

    for extension in availableExtensions.mitems:
        requiredExtensions.excl(extension.extensionName.cStringToString)
    return requiredExtensions.len == 0

proc querySwapChainSupport(self: HelloWorldApp, pDevice: VkPhysicalDevice): SwapChainSupportDetails =
    discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pDevice,self.surface,addr result.capabilities)
    var formatCount: uint32
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, self.surface, addr formatCount, nil)

    if formatCount != 0:
        result.formats.setLen(formatCount)
        discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, self.surface, formatCount.addr, result.formats[0].addr)
    var presentModeCount: uint32
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, self.surface, presentModeCount.addr, nil)
    if presentModeCount != 0:
        result.presentModes.setLen(presentModeCount)
        discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, self.surface, presentModeCount.addr, result.presentModes[0].addr)

proc chooseSwapSurfaceFormat(self: HelloWorldApp, availableFormats: seq[VkSurfaceFormatKHR]): VkSurfaceFormatKHR =
    for format in availableFormats:
        if format.format == VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
            return format
    return availableFormats[0]

proc chooseSwapPresnetMode(self: HelloWorldApp, availablePresentModes: seq[VkPresentModeKHR]): VkPresentModeKHR =
    for presentMode in availablePresentModes:
        if presentMode == VK_PRESENT_MODE_MAILBOX_KHR:
            return presentMode
    return VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent(self: HelloWorldApp, capabilities: VkSurfaceCapabilitiesKHR): VkExtent2D =
    if capabilities.currentExtent.width != uint32.high:
        return capabilities.currentExtent
    else:
        var width: int32
        var height: int32
        getFramebufferSize(self.window, addr width, addr height)
        result.width = clamp(cast[uint32](width),
                                capabilities.minImageExtent.width,
                                capabilities.maxImageExtent.width)
        result.height = clamp(cast[uint32](height),
                                capabilities.minImageExtent.height,
                                capabilities.maxImageExtent.height)

proc findQueueFamilies(self: HelloWorldApp, pDevice: VkPhysicalDevice): QueueFamilyIndices =
    var queueFamilyCount: uint32 = 0
    vkGetPhysicalDeviceQueueFamilyProperties(pDevice, addr queueFamilyCount, nil)
    var queueFamilies: seq[VkQueueFamilyProperties] = newSeq[VkQueueFamilyProperties](queueFamilyCount) # [TODO] this pattern can be templated
    vkGetPhysicalDeviceQueueFamilyProperties(pDevice, addr queueFamilyCount, addr queueFamilies[0])
    var index: uint32 = 0
    for queueFamily in queueFamilies:
        if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
            result.graphicsFamily = some(index)
        var presentSupport: VkBool32 = VkBool32(VK_FALSE)
        discard vkGetPhysicalDeviceSurfaceSupportKHR(pDevice, index, self.surface, addr presentSupport)
        if presentSupport.ord == 1:
            result.presentFamily = some(index)

        if(result.isComplete()):
            break
        index.inc

proc isDeviceSuitable(self: HelloWorldApp, pDevice: VkPhysicalDevice): bool =
    var deviceProperties: VkPhysicalDeviceProperties
    vkGetPhysicalDeviceProperties(pDevice, deviceProperties.addr)
    var indicies: QueueFamilyIndices = self.findQueueFamilies(pDevice)
    var extensionsSupported = self.checkDeviceExtensionSupport(pDevice)
    var swapChainAdequate = false
    if extensionsSupported:
        var swapChainSupport: SwapChainSupportDetails = self.querySwapChainSupport(pDevice)
        swapChainAdequate = swapChainSupport.formats.len != 0 and swapChainSupport.presentModes.len != 0
    return indicies.isComplete and extensionsSupported and swapChainAdequate

proc pickPhysicalDevice(self: HelloWorldApp) =
    var deviceCount: uint32 = 0
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, nil)
    if(deviceCount == 0):
        raise newException(RuntimeException, "failed to find GPUs with Vulkan support!")
    var pDevices: seq[VkPhysicalDevice] = newSeq[VkPhysicalDevice](deviceCount)
    discard vkEnumeratePhysicalDevices(self.instance, addr deviceCount, addr pDevices[0])
    for pDevice in pDevices:
        if self.isDeviceSuitable(pDevice):
            self.physicalDevice = pDevice
            return

    raise newException(RuntimeException, "failed to find a suitable GPU!")

proc createLogicalDevice(self: HelloWorldApp) =
    let
        indices = self.findQueueFamilies(self.physicalDevice)
        uniqueQueueFamilies = [indices.graphicsFamily.get, indices.presentFamily.get].toHashSet
    var
        queuePriority = 1f
        queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()

    for queueFamily in uniqueQueueFamilies:
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

    if not deviceExts.isNil:
        deallocCStringArray(deviceExts)

    vkGetDeviceQueue(self.device, indices.graphicsFamily.get, 0, addr self.graphicsQueue)
    vkGetDeviceQueue(self.device, indices.presentFamily.get, 0, addr self.presentQueue)


proc createSwapChain(self: HelloWorldApp) =
    let swapChainSupport: SwapChainSupportDetails = self.querySwapChainSupport(self.physicalDevice)

    let surfaceFormat: VkSurfaceFormatKHR = self.chooseSwapSurfaceFormat(swapChainSupport.formats)
    let presentMode: VkPresentModeKHR = self.chooseSwapPresnetMode(swapChainSupport.presentModes)
    let extent: VkExtent2D = self.chooseSwapExtent(swapChainSupport.capabilities)

    var imageCount: uint32 = swapChainSupport.capabilities.minImageCount + 1 # request one extra per recommended settings

    if swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount:
        imageCount = swapChainSupport.capabilities.maxImageCount

    var createInfo = VkSwapchainCreateInfoKHR(
        sType: cast[VkStructureType](1000001000), # VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
        surface: self.surface,
        minImageCount: imageCount,
        imageFormat: surfaceFormat.format,
        imageColorSpace: surfaceFormat.colorSpace,
        imageExtent: extent,
        imageArrayLayers: 1,
        imageUsage: VkImageUsageFlags(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
        preTransform: swapChainSupport.capabilities.currentTransform,
        compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        presentMode: presentMode,
        clipped: VKBool32(VK_TRUE),
        oldSwapchain: VkSwapchainKHR(0)#VK_NULL_HANDLE [TODO] Fix in vulkan to have definition
    )
    let indices = self.findQueueFamilies(self.physicalDevice)
    var queueFamilyIndicies = [indices.graphicsFamily.get, indices.presentFamily.get]

    if indices.graphicsFamily.get != indices.presentFamily.get:
        createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
        createInfo.queueFamilyIndexCount = 2
        createInfo.pQueueFamilyIndices = queueFamilyIndicies[0].addr
    else:
        createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
        createInfo.queueFamilyIndexCount = 0
        createInfo.pQueueFamilyIndices = nil

    if vkCreateSwapchainKHR(self.device, addr createInfo, nil, addr self.swapChain) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create swap chain!")
    discard vkGetSwapchainImagesKHR(self.device, self.swapChain, addr imageCount, nil)
    self.swapChainImages.setLen(imageCount)
    discard vkGetSwapchainImagesKHR(self.device, self.swapChain, addr imageCount, addr self.swapChainImages[0])
    self.swapChainImageFormat = surfaceFormat.format
    self.swapChainExtent = extent

proc createImageViews(self: HelloWorldApp) =
    self.swapChainImageViews.setLen(self.swapChainImages.len)
    for index, swapChainImage in self.swapChainImages:
        var createInfo = newVkImageViewCreateInfo(
            image = swapChainImage,
            viewType = VK_IMAGE_VIEW_TYPE_2D,
            format = self.swapChainImageFormat,
            components = newVkComponentMapping(VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY,VK_COMPONENT_SWIZZLE_IDENTITY),
            subresourceRange = newVkImageSubresourceRange(aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT), 0.uint32, 1.uint32, 0.uint32, 1.uint32)
        )
        if vkCreateImageView(self.device, addr createInfo, nil, addr self.swapChainImageViews[index]) != VK_SUCCESS:
            raise newException(RuntimeException, "failed to create image views")

proc createShaderModule(self: HelloWorldApp, code: string) : VkShaderModule =
    var createInfo = newVkShaderModuleCreateInfo(
        codeSize = code.len.uint32,
        pCode = cast[ptr uint32](code[0].unsafeAddr) #Hopefully reading bytecode as string is alright
    )
    if vkCreateShaderModule(self.device, addr createInfo, nil, addr result) != VK_SUCCESS:
        raise newException(RuntimeException, "failed to create shader module")

proc createRenderPass(self: HelloWorldApp) =
    var
        colorAttachment: VkAttachmentDescription = newVkAttachmentDescription(
            format = self.swapChainImageFormat,
            samples = VK_SAMPLE_COUNT_1_BIT,
            loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp = VK_ATTACHMENT_STORE_OP_STORE,
            stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout = cast[VkImageLayout](1000001002), # VK_IMAGE_LAYOUT_PRESENT_SRC_KHR Why is this not defined in vulkan.nim
        )
        colorAttachmentRef: VkAttachmentReference = newVkAttachmentReference(
            attachment = 0,
            layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        )
        subpass = VkSubpassDescription(
            pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount: 1,
            pColorAttachments: addr colorAttachmentRef,
        )
        dependency: VkSubpassDependency = VkSubpassDependency(
            srcSubpass: VK_SUBPASS_EXTERNAL,
            dstSubpass: 0,
            srcStageMask: VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            srcAccessMask: VkAccessFlags(0),
            dstStageMask: VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            dstAccessMask: VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT),
        )
        renderPassInfo: VkRenderPassCreateInfo = newVkRenderPassCreateInfo(
            attachmentCount = 1,
            pAttachments = addr colorAttachment,
            subpassCount = 1,
            pSubpasses = addr subpass,
            dependencyCount = 1,
            pDependencies = addr dependency,
        )
    if vkCreateRenderPass(self.device, addr renderPassInfo, nil, addr self.renderPass) != VK_SUCCESS:
        quit("failed to create render pass")

proc createGraphicsPipeline(self: HelloWorldApp) =
    const
        vertShaderCode: string = staticRead("./shaders/vert.spv")
        fragShaderCode: string = staticRead("./shaders/frag.spv")
    var
        vertShaderModule: VkShaderModule = self.createShaderModule(vertShaderCode)
        fragShaderModule: VkShaderModule = self.createShaderModule(fragShaderCode)
        vertShaderStageInfo: VkPipelineShaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
            stage = VK_SHADER_STAGE_VERTEX_BIT,
            module = vertShaderModule,
            pName = "main",
            pSpecializationInfo = nil
        )
        fragShaderStageInfo: VkPipelineShaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
            stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            module = fragShaderModule,
            pName = "main",
            pSpecializationInfo = nil
        )
        shaderStages: array[2, VkPipelineShaderStageCreateInfo] = [vertShaderStageInfo, fragShaderStageInfo]
        dynamicStates: array[2, VkDynamicState] = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
        dynamicState: VkPipelineDynamicStateCreateInfo = newVkPipelineDynamicStateCreateInfo(
            dynamicStateCount = dynamicStates.len.uint32,
            pDynamicStates = addr dynamicStates[0]
        )
        vertexInputInfo: VkPipelineVertexInputStateCreateInfo = newVkPipelineVertexInputStateCreateInfo(
            vertexBindingDescriptionCount = 0,
            pVertexBindingDescriptions = nil,
            vertexAttributeDescriptionCount = 0,
            pVertexAttributeDescriptions = nil
        )
        inputAssembly: VkPipelineInputAssemblyStateCreateInfo = newVkPipelineInputAssemblyStateCreateInfo(
            topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable = VkBool32(VK_FALSE)
        )
        viewport: VkViewPort = newVkViewport(
            x = 0.float,
            y = 0.float,
            width = self.swapChainExtent.width.float,
            height = self.swapChainExtent.height.float,
            minDepth = 0.float,
            maxDepth = 1.float
        )
        scissor: VkRect2D = newVkRect2D(
            offset = newVkOffset2D(0,0),
            extent = self.swapChainExtent
        )
        viewportState: VkPipelineViewportStateCreateInfo = newVkPipelineViewportStateCreateInfo(
            viewportCount = 1,
            pViewports = addr viewport,
            scissorCount = 1,
            pScissors = addr scissor
        )
        rasterizer: VkPipelineRasterizationStateCreateInfo = newVkPipelineRasterizationStateCreateInfo(
            depthClampEnable = VkBool32(VK_FALSE), # [TODO] VkBool32 should really be an enum
            rasterizerDiscardEnable = VkBool32(VK_FALSE),
            polygonMode = VK_POLYGON_MODE_FILL,
            lineWidth = 1.float,
            cullMode = VkCullModeFlags(VK_CULL_MODE_BACK_BIT),
            frontface = VK_FRONT_FACE_CLOCKWISE,
            depthBiasEnable = VKBool32(VK_FALSE),
            depthBiasConstantFactor = 0.float,
            depthBiasClamp = 0.float,
            depthBiasSlopeFactor = 0.float,
        )
        multisampling: VkPipelineMultisampleStateCreateInfo = newVkPipelineMultisampleStateCreateInfo(
            sampleShadingEnable = VkBool32(VK_FALSE),
            rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
            minSampleShading = 1.float,
            pSampleMask = nil,
            alphaToCoverageEnable = VkBool32(VK_FALSE),
            alphaToOneEnable = VkBool32(VK_FALSE)
        )
        # [NOTE] Not doing VkPipelineDepthStencilStateCreateInfo because we don't have a depth or stencil buffer yet
        colorBlendAttachment: VkPipelineColorBlendAttachmentState = newVkPipelineColorBlendAttachmentState(
            colorWriteMask = VkColorComponentFlags(bitor(VK_COLOR_COMPONENT_R_BIT.int32, bitor(VK_COLOR_COMPONENT_G_BIT.int32, bitor(VK_COLOR_COMPONENT_B_BIT.int32, VK_COLOR_COMPONENT_A_BIT.int32)))),
            blendEnable = VkBool32(VK_FALSE),
            srcColorBlendFactor = VK_BLEND_FACTOR_ONE, # optional
            dstColorBlendFactor = VK_BLEND_FACTOR_ZERO, # optional
            colorBlendOp = VK_BLEND_OP_ADD, # optional
            srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE, # optional
            dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO, # optional
            alphaBlendOp = VK_BLEND_OP_ADD, # optional
        )
        colorBlending: VkPipelineColorBlendStateCreateInfo = newVkPipelineColorBlendStateCreateInfo(
            logicOpEnable = VkBool32(VK_FALSE),
            logicOp = VK_LOGIC_OP_COPY, # optional
            attachmentCount = 1,
            pAttachments = colorBlendAttachment.addr,
            blendConstants = [0f, 0f, 0f, 0f], # optional
        )
        pipelineLayoutInfo: VkPipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
            setLayoutCount = 0, # optional
            pSetLayouts = nil, # optional
            pushConstantRangeCount = 0, # optional
            pPushConstantRanges = nil, # optional
        )
    if vkCreatePipelineLayout(self.device, pipelineLayoutInfo.addr, nil, addr self.pipelineLayout) != VK_SUCCESS:
        quit("failed to create pipeline layout")
    var
        pipelineInfo: VkGraphicsPipelineCreateInfo = newVkGraphicsPipelineCreateInfo(
            stageCount = shaderStages.len.uint32,
            pStages = shaderStages[0].addr,
            pVertexInputState = vertexInputInfo.addr,
            pInputAssemblyState = inputAssembly.addr,
            pViewportState = viewportState.addr,
            pRasterizationState = rasterizer.addr,
            pMultisampleState = multisampling.addr,
            pDepthStencilState = nil, # optional
            pColorBlendState = colorBlending.addr,
            pDynamicState = nil, # optional
            pTessellationState = nil,
            layout = self.pipelineLayout,
            renderPass = self.renderPass,
            subpass = 0,
            basePipelineHandle = VkPipeline(0), # optional
            basePipelineIndex = -1, # optional
        )
    if vkCreateGraphicsPipelines(self.device, VkPipelineCache(0), 1, pipelineInfo.addr, nil, addr self.graphicsPipeline) != VK_SUCCESS:
        quit("fialed to create graphics pipeline")
    vkDestroyShaderModule(self.device, vertShaderModule, nil)
    vkDestroyShaderModule(self.device, fragShaderModule, nil)

proc initVulkan(self: HelloWorldApp) =
    self.createInstance()
    self.createSurface()
    self.pickPhysicalDevice()
    self.createLogicalDevice()
    self.createSwapChain()
    self.createImageViews()
    self.createRenderPass()
    self.createGraphicsPipeline()

proc mainLoop(self: HelloWorldApp) =
    while not windowShouldClose(self.window):
        glfwPollEvents()

proc cleanup(self: HelloWorldApp) =
    vkDestroyPipeline(self.device, self.graphicsPipeline, nil)
    vkDestroyPipelineLayout(self.device, self.pipelineLayout, nil)
    for imageView in self.swapChainImageViews:
        vkDestroyImageView(self.device, imageView, nil)
    vkDestroySwapchainKHR(self.device, self.swapChain, nil)
    vkDestroyDevice(self.device, nil) #destroy device before instance
    vkDestroySurfaceKHR(self.instance, self.surface, nil)
    vkDestroyInstance(self.instance, nil)
    self.window.destroyWindow()
    glfwTerminate()

proc run*(self: HelloWorldApp) =
    self.initWindow()
    self.initVulkan()
    self.mainLoop()
    self.cleanup()