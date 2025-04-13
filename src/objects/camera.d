import includes;

import std.math : cos, sin;

import vector : normalize, vMul, vAdd, negate, xyz;
import matrix : Matrix, multiply, rotate, radian;
import quaternion : xyzw;

struct Camera {
    @nogc float[3] position() const nothrow {
      return(vAdd(lookat, vMul(rotation.direction(), distance)));
    }
    float[3]     lookat      = [0.0f, 0.0f, 0.0f];    // Position in the middle of the screen
    float[2]     nearfar     = [0.1f, 100.0f];        // View distances, near [0], far [1]
    float[3]     up          = [0.0f, 1.0f, 0.0f];    // Defined up vector
    float        fov         = 45.0f;                 // Field of view

    float[3]     rotation    = [0.0f, 0.0f, 0.0f];    // Horizontal [0], Vertical [1]
    float        distance    = 2.0f;                  // Distance of camera to lookat
    
    bool[2]      isdrag        = [false, false];

    // Move the camera forward
    @property @nogc float[3] forward() const nothrow { 
      float[3] direction = rotation.direction();

      direction.normalize();
      direction = direction.vMul(-0.1f);
      return(direction);
    }

    // Move the camera backward
    @property @nogc float[3] back() const nothrow { 
      float[3] back = -forward()[];
      return(back);
    }

    // Move the camera to the left of the view direction
    @property @nogc float[3] left() const nothrow {
      float[3] direction = forward();
      direction[1] = 0.0f;
      float[3] left = multiply(rotate(Matrix.init, [0.0f, -90.0f, 0.0f]), direction.xyzw()).xyz;
      return(left);
    }

    // Move the camera to the right of the view direction
    @property @nogc float[3] right() const nothrow { 
      float[3] right = -left()[];
      return(right);
    }
}

/* Get the normalized direction of the xy camera rotation (gimbal lock) */
@nogc float[3] direction(const float[3] rotation) nothrow {
    float[3] direction = [
        cos(radian(rotation[1])) * cos(radian(rotation[0])),
        sin(radian(rotation[1])),
        cos(radian(rotation[1])) * sin(radian(rotation[0])),
    ];
    direction.normalize();
    direction.negate();
    return(direction);
}

@nogc void move(ref Camera camera, float[3] movement) nothrow {
    camera.lookat = vAdd(camera.lookat, movement);
}

/* Drag the camera in the x/y directions, causes camera rotation */
@nogc void drag(ref Camera camera, float xrel, float yrel) nothrow {
    camera.rotation[0] -= xrel; 
    if(camera.rotation[0]  > 360) camera.rotation[0] = 0;
    if(camera.rotation[0]  < 0) camera.rotation[0] = 360;

    camera.rotation[1] -= yrel;
    if(camera.rotation[1]  > 65) camera.rotation[1] = 65;
    if(camera.rotation[1]  < -65) camera.rotation[1] = -65;
}
