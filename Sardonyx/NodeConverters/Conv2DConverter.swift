import Foundation

class Conv2DConverter: NodeConverter {
    func prepareData(using context: GenerationContext) throws {
        guard
            let weight = context.tensors[self.node.input[1]]
        else { fatalError() }
        
        var bias: Onnx_TensorProto?
        if self.node.input.count > 2 {
            bias = context.tensors[node.input[2]]
        }
        
        
        let weightData = weight.floatData.transposed(to: [2, 3, 1, 0],
                                                     assuming: weight.dims.map(Int.init)).withUnsafeBufferPointer { pointer -> Data in
            return Data(buffer: pointer)
        }
        let biasData = bias?.floatData.withUnsafeBufferPointer { pointer -> Data in
            return Data(buffer: pointer)
        }
        
        self.weightOffset = context.add(data: weightData)
        self.outputChannels = Int(weight.dims[0])
        self.inputChannels = Int(weight.dims[1])
        if let bd = biasData {
            self.biasOffset = context.add(data: bd)
        }
    }
    
    func contributeProperties(using: GenerationContext) -> String {
        "var layer_\(self.node.name): Conv2D<Float>\n"
    }
    
    func contributeInit(using: GenerationContext) -> String {
        let wInit = "let weight_\(self.node.name) = Tensor<Float>(shape: [\(self.kernel.height), \(self.kernel.width), \(self.inputChannels), \(self.outputChannels)], scalars: UnsafeBufferPointer<Float>(start: data.advanced(by: \(self.weightOffset)).assumingMemoryBound(to: Float.self), count: \(self.kernel.width * self.kernel.height * self.inputChannels * self.outputChannels)), on: Device.defaultXLA)\n"
        let bInit: String
        if self.hasBias {
            bInit = "let bias_\(self.node.name) = Tensor<Float>(shape: [\(self.outputChannels)], scalars: UnsafeBufferPointer<Float>(start: data.advanced(by: \(self.biasOffset!)).assumingMemoryBound(to: Float.self), count: \(self.outputChannels)), on: Device.defaultXLA)\n"
        } else {
            bInit = "let bias_\(self.node.name): Tensor<Float>? = nil\n"
        }
        
        let convInit = "self.layer_\(self.node.name) = Conv2D<Float>(filter: weight_\(self.node.name), bias: bias_\(self.node.name), activation: { $0 }, strides: (\(self.strides.width), \(self.strides.height)), padding: .\(self.padding), dilations: (\(self.dilations.width), \(self.dilations.height)))\n"
        
        return wInit + bInit + convInit
    }
    
    func contributeImplementation(using: GenerationContext) -> String {
        let outputname = self.node.output[0]
        return "let _\(outputname) = self.layer_\(self.node.name)(_\(self.node.input[0]))\n"
    }
    
    let node: Onnx_NodeProto
    let hasBias: Bool
    var weightOffset: Int = 0
    var inputChannels: Int = 0
    var outputChannels: Int = 0
    var biasOffset: Int? = nil
    
    let kernel: Kernel
    let dilations: Dilations
    let strides: Strides
    
    let padding: String
    
    required init(node: Onnx_NodeProto) {
        self.node = node
        self.hasBias = node.input.count > 2
        var kernel: Kernel = (1, 1)
        var dilations: Dilations = (1, 1)
        var strides: Strides = (1, 1)
        var groups: Int = 1
        var pads: Pads = (0, 0, 0, 0)
        var outputPadding = Padding(height: 0, width: 0)
        
        for attr in node.attribute {
            switch attr.name {
            case "dilations":
                dilations = (Int(attr.ints[0]), Int(attr.ints[1]))
            case "strides":
                strides = (Int(attr.ints[0]), Int(attr.ints[1]))
            case "group":
                groups = Int(attr.i)
            case "pads":
                pads = (Int(attr.ints[0]), Int(attr.ints[1]), Int(attr.ints[2]), Int(attr.ints[3]))
            case "kernel_shape":
                kernel = (Int(attr.ints[0]), Int(attr.ints[1]))
            case "output_padding":
                outputPadding = (Int(attr.ints[0]), Int(attr.ints[1]))
            default:
                break
            }
        }
        
        if pads == (0, 0, 0, 0) {
            self.padding = "valid"
        } else if pads == (1, 1, 1, 1) {
            self.padding = "same"
        } else {
            fatalError("Please implement logic for padding: \(pads)")
        }
        
        self.kernel = kernel
        self.dilations = dilations
        self.strides = strides
    }
}