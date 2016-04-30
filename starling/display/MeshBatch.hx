// =================================================================================================
//
//	Starling Framework
//	Copyright Gamua GmbH. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.display;
import flash.geom.Matrix;

import starling.rendering.IndexData;
import starling.rendering.MeshEffect;
import starling.rendering.MeshStyle;
import starling.rendering.Painter;
import starling.rendering.VertexData;
import starling.utils.MeshSubset;

/** Combines a number of meshes to one display object and renders them efficiently.
 *
 *  <p>The most basic tangible (non-container) display object in Starling is the Mesh.
 *  However, a mesh typically does not render itself; it just holds the data describing its
 *  geometry. Rendering is orchestrated by the "MeshBatch" class. As its name suggests, it
 *  acts as a batch for an arbitrary number of Mesh instances; add meshes to a batch and they
 *  are all rendered together, in one draw call.</p>
 *
 *  <p>You can only batch meshes that share similar properties, e.g. they need to have the
 *  same texture and the same blend mode. The first object you add to a batch will decide
 *  this state; call <code>canAddMesh</code> to find out if a new mesh shares that state.
 *  To reset the current state, you can call <code>clear</code>; this will also remove all
 *  geometry that has been added thus far.</p>
 *
 *  <p>Starling will use MeshBatch instances (or compatible objects) for all rendering.
 *  However, you can also instantiate MeshBatch instances yourself and add them to the display
 *  tree. That makes sense for an object containing a large number of meshes; that way, that
 *  object can be created once and then rendered very efficiently, without having to copy its
 *  vertices and indices between buffers and GPU memory.</p>
 *
 *  @see Mesh
 *  @see Sprite
 */
class MeshBatch extends Mesh
{
    /** The maximum number of vertices that fit into one MeshBatch. */
    inline public static var MAX_NUM_VERTICES:Int = 65535;

    private var _effect:MeshEffect;
    private var _batchable:Bool;
    private var _vertexSyncRequired:Bool;
    private var _indexSyncRequired:Bool;

    // helper object
    private static var sFullMeshSubset:MeshSubset = new MeshSubset();

    /** Creates a new, empty MeshBatch instance. */
    public function new()
    {
        var vertexData:VertexData = new VertexData();
        var indexData:IndexData = new IndexData();

        super(vertexData, indexData);

        _batchable = true;
    }

    // display object overrides

    /** @inheritDoc */
    override public function dispose():Void
    {
        if (_effect != null) _effect.dispose();
        super.dispose();
    }

    /** @inheritDoc */
    @:noCompletion override private function get_supportsRenderCache():Bool
    {
        return _batchable && super.supportsRenderCache;
    }

    private function setVertexAndIndexDataChanged():Void
    {
        _vertexSyncRequired = _indexSyncRequired = true;
    }

    private function syncVertexBuffer():Void
    {
        _effect.uploadVertexData(_vertexData);
        _vertexSyncRequired = false;
    }

    private function syncIndexBuffer():Void
    {
        _effect.uploadIndexData(_indexData);
        _indexSyncRequired = false;
    }

    /** Removes all geometry. */
    public function clear():Void
    {
        _vertexData.numVertices = 0;
        _indexData.numIndices   = 0;
        _vertexSyncRequired = true;
        _indexSyncRequired  = true;
    }

    /** Adds a mesh to the batch by appending its vertices and indices.
     *
     *  @param mesh      the mesh to add to the batch.
     *  @param matrix    transform all vertex positions with a certain matrix. If this
     *                   parameter is omitted, <code>mesh.transformationMatrix</code>
     *                   will be used instead (except if the last parameter is enabled).
     *  @param alpha     will be multiplied with each vertex' alpha value.
     *  @param subset    the subset of the mesh you want to add, or <code>null</code> for
     *                   the complete mesh.
     *  @param ignoreTransformations   when enabled, the mesh's vertices will be added
     *                   without transforming them in any way (no matter the value of the
     *                   <code>matrix</code> parameter).
     */
    public function addMesh(mesh:Mesh, matrix:Matrix=null, alpha:Float=1.0,
                            subset:MeshSubset=null, ignoreTransformations:Bool=false):Void
    {
        if (ignoreTransformations) matrix = null;
        else if (matrix == null) matrix = mesh.transformationMatrix;
        if (subset == null) subset = sFullMeshSubset;

        var targetVertexID:Int = _vertexData.numVertices;
        var targetIndexID:Int  = _indexData.numIndices;
        var meshStyle:MeshStyle = mesh._style;

        if (targetVertexID == 0)
            setupFor(mesh);

        meshStyle.batchVertexData(_style, targetVertexID, matrix, subset.vertexID, subset.numVertices);
        meshStyle.batchIndexData(_style, targetIndexID, targetVertexID - subset.vertexID,
            subset.indexID, subset.numIndices);

        if (alpha != 1.0) _vertexData.scaleAlphas("color", alpha, targetVertexID, subset.numVertices);
        if (_batchable) setRequiresRedraw();

        _indexSyncRequired = _vertexSyncRequired = true;
    }

    /** Adds a mesh to the batch by copying its vertices and indices to the given positions.
     *  Beware that you need to check for yourself if those positions make sense; for example,
     *  you need to make sure that they are aligned within the 3-indices groups making up
     *  the mesh's triangles.
     *
     *  <p>It's easiest to only add objects with an identical setup, e.g. only quads.
     *  For the latter, indices are aligned in groups of 6 (one quad requires six indices),
     *  and the vertices in groups of 4 (one vertex for every corner).</p>
     */
    public function addMeshAt(mesh:Mesh, indexID:Int, vertexID:Int):Void
    {
        var numIndices:Int = mesh.numIndices;
        var numVertices:Int = mesh.numVertices;
        var matrix:Matrix = mesh.transformationMatrix;
        var meshStyle:MeshStyle = mesh._style;

        if (_vertexData.numVertices == 0)
            setupFor(mesh);

        meshStyle.batchVertexData(_style, vertexID, matrix, 0, numVertices);
        meshStyle.batchIndexData(_style, indexID, vertexID, 0, numIndices);

        if (alpha != 1.0) _vertexData.scaleAlphas("color", alpha, vertexID, numVertices);
        if (_batchable) setRequiresRedraw();

        _indexSyncRequired = _vertexSyncRequired = true;
    }

    private function setupFor(mesh:Mesh):Void
    {
        var meshStyle:MeshStyle = mesh._style;
        var meshStyleType:Class<MeshStyle> = meshStyle.type;

        if (_style.type != meshStyleType)
            setStyle(Type.createInstance(meshStyleType, []), false);

        _style.copyFrom(meshStyle);
    }

    /** Indicates if the given mesh instance fits to the current state of the batch.
     *  Will always return <code>true</code> for the first added mesh; later calls
     *  will check if the style matches and if the maximum number of vertices is not
     *  exceeded.
     *
     *  @param mesh         the mesh to add to the batch.
     *  @param numVertices  if <code>-1</code>, <code>mesh.numVertices</code> will be used
     */
    public function canAddMesh(mesh:Mesh, numVertices:Int=-1):Bool
    {
        var currentNumVertices:Int = _vertexData.numVertices;

        if (currentNumVertices == 0) return true;
        if (numVertices  < 0) numVertices = mesh.numVertices;
        if (numVertices == 0) return true;
        if (numVertices + currentNumVertices > MAX_NUM_VERTICES) return false;

        return _style.canBatchWith(mesh._style);
    }

    /** If the <code>batchable</code> property is enabled, this method will add the batch
     *  to the painter's current batch. Otherwise, this will actually do the drawing. */
    override public function render(painter:Painter):Void
    {
        if (_vertexData.numVertices == 0)
        {
            // nothing to do =)
        }
        else if (_batchable)
        {
            painter.batchMesh(this);
        }
        else
        {
            painter.finishMeshBatch();
            painter.drawCount += 1;
            painter.prepareToDraw();

            if (_vertexSyncRequired) syncVertexBuffer();
            if (_indexSyncRequired)  syncIndexBuffer();

            _style.updateEffect(_effect, painter.state);
            _effect.render(0, _indexData.numTriangles);
        }
    }

    /** @inheritDoc */
    override public function setStyle(meshStyle:MeshStyle=null,
                                      mergeWithPredecessor:Bool=true):Void
    {
        super.setStyle(meshStyle, mergeWithPredecessor);

        if (_effect != null)
            _effect.dispose();

        _effect = style.createEffect();
        _effect.onRestore = setVertexAndIndexDataChanged;
    }

    /** The total number of vertices in the mesh. If you change this to a smaller value,
     *  the surplus will be deleted. Make sure that no indices reference those deleted
     *  vertices! */
    @:noCompletion private override function set_numVertices(value:Int):Int
    {
        _vertexData.numVertices = value;
        _vertexSyncRequired = true;
        return value;
    }

    /** The total number of indices in the mesh. If you change this to a smaller value,
     *  the surplus will be deleted. Always make sure that the number of indices
     *  is a multiple of three! */
    @:noCompletion private override function set_numIndices(value:Int):Int
    {
        _indexData.numIndices = value;
        _indexSyncRequired = true;
        return value;
    }

    /** Indicates if this object will be added to the painter's batch on rendering,
     *  or if it will draw itself right away.
     *
     *  <p>Only batchable meshes can profit from the render cache; but batching large meshes
     *  may take up a lot of CPU time. Thus, for meshes that contain a large number of vertices
     *  or are constantly changing (i.e. can't use the render cache anyway), it makes
     *  sense to deactivate batching.</p>
     *
     *  @default true
     */
    public var batchable(get, set):Bool;
    @:noCompletion private function get_batchable():Bool { return _batchable; }
    @:noCompletion private function set_batchable(value:Bool):Bool
    {
        if (value != _batchable) // self-rendering must disrupt the render cache
        {
            _batchable = value;
            updateSupportsRenderCache();
        }
        return value;
    }
}