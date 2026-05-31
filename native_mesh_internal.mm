#include "native_mesh_internal.hpp"

namespace doof_game {
namespace native_mesh {

id<MTLSamplerState> linearSampler(id<MTLDevice> device, MTLSamplerAddressMode sAddressMode) {
    if (device == nil) {
        return nil;
    }

    static id<MTLSamplerState> clampSampler = nil;
    static id<MTLSamplerState> repeatSampler = nil;
    id<MTLSamplerState>* sampler = sAddressMode == MTLSamplerAddressModeRepeat ? &repeatSampler : &clampSampler;
    if (*sampler != nil) {
        return *sampler;
    }

    MTLSamplerDescriptor* descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter = MTLSamplerMinMagFilterLinear;
    descriptor.magFilter = MTLSamplerMinMagFilterLinear;
    descriptor.sAddressMode = sAddressMode;
    descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    *sampler = [device newSamplerStateWithDescriptor:descriptor];
    [descriptor release];
    return *sampler;
}

}  // namespace native_mesh
}  // namespace doof_game
