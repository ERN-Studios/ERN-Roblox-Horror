"""Small geometry checks for the diagnostic itself; no game fixtures or edits."""
import math
import unittest
import audit_surface_faces as audit


def row(name,x=0,y=0,z=0,size=(10,1,10),angle=0,variant="Carpet"):
    c,s=math.cos(angle),math.sin(angle)
    return {"path":name,"name":name,"class":"Part","transparency":0,"material":"Enum.Material.Fabric","variant":variant,
            "size":list(size),"cf":[x,y,z,c,0,s,0,1,0,-s,0,c],"color":[1,1,1]}


class SurfaceAuditChecks(unittest.TestCase):
    def test_rectangles_clip_partial_overlap(self):
        a=[(0,0),(10,0),(10,10),(0,10)];b=[(7,3),(15,3),(15,7),(7,7)]
        self.assertAlmostEqual(audit.polygon_area(audit.intersection(a,b)),12)

    def test_touching_edges_have_no_area(self):
        a=[(0,0),(10,0),(10,10),(0,10)];b=[(10,0),(20,0),(20,10),(10,10)]
        self.assertAlmostEqual(audit.polygon_area(audit.intersection(a,b)),0)

    def test_yawed_top_face_uses_real_polygon(self):
        boxes,_,_=audit.prepare([row("rotated",angle=math.pi/4)])
        face=next(f for f in audit.faces_for(boxes[0],0,1) if f["axis"]==1 and f["sign"]==1)
        self.assertAlmostEqual(audit.polygon_area(face["poly"]),100)
        self.assertGreater((face["max"][0]-face["min"][0])*(face["max"][1]-face["min"][1]),190)

    def test_duplicate_top_exposed_when_pair_excluded(self):
        boxes,grid,_=audit.prepare([row("a"),row("b")])
        fs=[next(f for f in audit.faces_for(b,i,1) if f["axis"]==1 and f["sign"]==1) for i,b in enumerate(boxes)]
        visible,total,*_=audit.visibility(fs[0]["poly"],*fs,boxes,grid)
        self.assertEqual(visible,total)

    def test_wholly_buried_pair_is_suppressed(self):
        boxes,grid,_=audit.prepare([row("a"),row("b"),row("cover",y=1,size=(20,2,20))])
        fs=[next(f for f in audit.faces_for(boxes[i],i,1) if f["axis"]==1 and f["sign"]==1) for i in range(2)]
        visible,*_=audit.visibility(fs[0]["poly"],*fs,boxes,grid)
        self.assertEqual(visible,0)

    def test_partial_cover_retains_candidate(self):
        boxes,grid,_=audit.prepare([row("a"),row("b"),row("cover",x=-5,y=1,size=(10,2,20))])
        fs=[next(f for f in audit.faces_for(boxes[i],i,1) if f["axis"]==1 and f["sign"]==1) for i in range(2)]
        visible,total,*_=audit.visibility(fs[0]["poly"],*fs,boxes,grid)
        self.assertGreater(visible,0);self.assertLess(visible,total)

    def test_opposite_face_normals_stay_distinct(self):
        boxes,_,_=audit.prepare([row("a")]);fs=list(audit.faces_for(boxes[0],0,1))
        up=next(f for f in fs if f["axis"]==1 and f["sign"]==1)
        down=next(f for f in fs if f["axis"]==1 and f["sign"]==-1)
        self.assertNotEqual((up["axis"],up["sign"]),(down["axis"],down["sign"]))

    def test_unknown_wedge_and_glass_not_used_as_block_occluders(self):
        wedge=row("w");wedge["class"]="WedgePart"
        glass=row("g");glass["transparency"]=.2
        boxes,_,skip=audit.prepare([wedge,glass])
        self.assertEqual(boxes,[]);self.assertEqual(skip["nonopaque"],1);self.assertEqual(skip["nonbox_class"],1)

    def test_export_material_spellings_are_equivalent(self):
        for spelling in ("Fabric","Enum.Material.Fabric"):
            item=row("floor");item["material"]=spelling
            boxes,_,_=audit.prepare([item])
            face=next(f for f in audit.faces_for(boxes[0],0,1) if f["axis"]==1 and f["sign"]==1)
            self.assertTrue(audit.is_textured(item));self.assertTrue(audit.floor_like(face,boxes))
        for spelling in ("SmoothPlastic","Enum.Material.SmoothPlastic"):
            item=row("smooth",variant="");item["material"]=spelling
            self.assertFalse(audit.is_textured(item))


if __name__=="__main__":unittest.main()
