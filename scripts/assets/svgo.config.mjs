export default {
  multipass: true,
  floatPrecision: 3,
  plugins: [{
    name: 'preset-default',
    params: {
      overrides: {
        // Keep existing short IDs stable when definition sorting changes reference order.
        cleanupIds: { minify: false },
        // The native loader reads text attributes directly; RTL replaces selected group transforms.
        removeUnknownsAndDefaults: false,
        removeHiddenElems: false,
        moveElemsAttrsToGroup: false,
        moveGroupAttrsToElems: false,
        collapseGroups: false,
        convertShapeToPath: false,
        convertTransform: false,
        mergePaths: false,
        convertPathData: { applyTransforms: false },
        removeDesc: false,
      },
    },
  }],
};
